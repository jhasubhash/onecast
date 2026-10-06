import AppKit
import AVFoundation

@MainActor
@Observable
final class DictationCoordinator {
    private enum Phase { case idle, starting, listening, transcribing, stopping }

    private let settings: AppSettings
    private let hotKeys: HotKeyManager
    let models: DictationModelStore
    private let capture = DictationCapture()
    private let audioDucker: DictationAudioDucker
    private let panel = DictationPanelController()
    private let injector: TextInjector
    private let showMessage: (String, DialogTone) -> Void
    private let confirmEnable: () async -> Bool
    @ObservationIgnored private var phase: Phase = .idle
    @ObservationIgnored private var token = UUID()
    @ObservationIgnored private var enableTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var transcriptionTask: Task<Void, Never>?
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var finishWhenStarted = false
    @ObservationIgnored private var target: InjectionTarget?
    @ObservationIgnored private var live: LiveTyping?
    /// The field a mic button is dictating into; nil for a shortcut's session.
    private(set) var field: DictationField?

    init(
        settings: AppSettings, hotKeys: HotKeyManager, models: DictationModelStore,
        injector: TextInjector, audioDucker: DictationAudioDucker,
        confirmEnable: @escaping () async -> Bool,
        showMessage: @escaping (String, DialogTone) -> Void
    ) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.models = models
        self.injector = injector
        self.audioDucker = audioDucker
        self.confirmEnable = confirmEnable
        self.showMessage = showMessage
        panel.onAccept = { [weak self] in self?.accept() }
        panel.onCancel = { [weak self] in self?.cancel() }
        capture.onLevels = { [weak self] in self?.panel.state.levels = $0 }
        capture.onLimit = { [weak self] in self?.accept() }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != settings.dictationEnabled else { return }
        guard enabled else {
            settings.dictationEnabled = false
            enableTask?.cancel()
            cancel()
            return
        }
        guard enableTask == nil else { return }
        NSApp.activate()
        enableTask = Task { [weak self] in
            guard let self else { return }
            defer { enableTask = nil }
            guard await confirmEnable(), !Task.isCancelled else { return }
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard !Task.isCancelled else { return }
            guard granted else {
                showMessage("Allow Onecast to use the microphone in System Settings", .danger)
                return
            }
            settings.dictationEnabled = true
            if settings.dictationDestination.pastes { Permissions.ensureAccessibility() }
        }
    }

    func downloadModel(_ model: DictationModel) async {
        do { try await models.download(model) } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch { showMessage(error.localizedDescription, .danger) }
    }

    func removeModel(_ model: DictationModel) async {
        do { try await models.delete(model) } catch { showMessage(error.localizedDescription, .danger) }
    }

    var holdShortcutIssue: String? {
        guard let binding = hotKeys.binding(for: .dictation) else { return nil }
        guard binding.shortcut != nil || binding.holdKey != nil else {
            return "Record a single modifier or a key combination for hold to talk."
        }
        if let owner = hotKeys.conflictOwner(of: binding, excluding: .dictation) {
            return "This shortcut is also used by \(owner). Record another shortcut."
        }
        return nil
    }

    func pressed() {
        guard settings.dictationEnabled else { return }
        if phase == .stopping { return }
        if settings.dictationMode == .pushToTalk,
            hotKeys.binding(for: .dictation)?.shortcut == nil,
            hotKeys.binding(for: .dictation)?.holdKey == nil
        {
            showMessage("Hold to talk needs a key combination or a single modifier", .danger)
            return
        }
        if phase != .idle {
            if settings.dictationMode == .toggle { finish() }
            return
        }
        begin(target: InjectionTarget.current())
    }

    var isEnabled: Bool { settings.dictationEnabled }
    var hasModel: Bool { models.isInstalled(settings.dictationModel) }

    /// A field's own mic: click to start, click to finish, whatever the shortcut's mode or focus.
    func toggle(into editor: any InjectableTextView) {
        guard settings.dictationEnabled, phase != .stopping else { return }
        guard phase == .idle else {
            if field?.editor == ObjectIdentifier(editor) { finish() }
            return
        }
        field = DictationField(editor: ObjectIdentifier(editor))
        begin(target: .ownEditor(editor))
    }

    private func finish() {
        if phase == .starting {
            finishWhenStarted = true
        } else {
            accept()
        }
    }

    private func begin(target: InjectionTarget?) {
        guard models.isInstalled(settings.dictationModel) else {
            field = nil
            showMessage("Download the dictation model in Settings first", .danger)
            return
        }
        token = UUID()
        let current = token
        phase = .starting
        finishWhenStarted = false
        self.target = target
        panel.state.isLive =
            settings.dictationTypesWhileSpeaking && !settings.dictationModel.isQwen
            && (field != nil || settings.dictationDestination.pastes)
        audioDucker.begin()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await capture.start(microphoneID: settings.dictationMicrophone)
                guard token == current, settings.dictationEnabled else {
                    _ = await capture.stop()
                    return
                }
                phase = .listening
                if panel.state.isLive { startLiveTyping(token: current) }
                panel.show()
                if finishWhenStarted { accept() }
            } catch {
                guard token == current else { return }
                reset()
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    func released() {
        guard settings.dictationMode == .pushToTalk else { return }
        if phase == .starting { finishWhenStarted = true }
        if phase == .listening { accept() }
    }

    func accept() {
        guard phase == .listening else { return }
        phase = .transcribing
        panel.state.phase = .transcribing
        field?.isTranscribing = true
        audioDucker.end()
        let current = token
        let model = settings.dictationModel
        let language = settings.dictationLanguage
        transcriptionTask = Task { [weak self] in
            guard let self else { return }
            let samples = await capture.stop()
            guard token == current else { return }
            if let live {
                await finishLiveTyping(live, samples: samples, token: current)
                return
            }
            guard samples.count >= 1_600 else {
                reset(cancelTranscription: false)
                showMessage("No speech was recorded", .danger)
                return
            }
            do {
                let transcript = try await models.transcribe(
                    samples, model: model,
                    language: language)
                guard token == current else { return }
                // A mic belongs to its field: the text goes in there, never to the clipboard.
                let destination = field == nil ? settings.dictationDestination : .paste
                let context = destination.pastes ? DictationInsertionContext.read(in: target) : nil
                let text = DictationTextFormatter.format(
                    transcript, context: context,
                    adaptCapitalization: settings.dictationAdaptsCapitalization)
                let target = self.target
                guard !text.isEmpty else { reset(cancelTranscription: false); return }
                panel.close()
                if destination.pastes {
                    injector.deliver(
                        InjectedText(text), target: target, expectedKeyword: nil,
                        keywordLength: 0, automaticGeneration: nil,
                        isValid: { [weak self] in self?.token == current },
                        onDelivered: { [weak self] in
                            guard let self, token == current else { return }
                            if destination.copies { Paster.copyPlainText(text) }
                            reset(cancelTranscription: false)
                        },
                        onFailed: { [weak self] in
                            guard let self, token == current else { return }
                            reset(cancelTranscription: false)
                            if destination.copies { Paster.copyPlainText(text) }
                            showMessage("Couldn't paste dictation into this app", .danger)
                        })
                } else {
                    Paster.copyPlainText(text)
                    reset(cancelTranscription: false)
                }
            } catch {
                guard token == current else { return }
                reset(cancelTranscription: false)
                showMessage(error.localizedDescription, .danger)
            }
        }
    }

    func cancel(in editor: any InjectableTextView) {
        guard let target = target?.ownEditor, target === editor else { return }
        cancel()
    }

    func cancel() {
        guard phase != .stopping, phase != .idle || !settings.dictationEnabled else { return }
        let pendingStart = startTask
        let pendingTranscription = transcriptionTask
        let pendingLive = live?.task
        reset()
        phase = .stopping
        let current = token
        stopTask = Task { [weak self] in
            guard let self else { return }
            await pendingStart?.value
            _ = await capture.stop()
            await pendingTranscription?.value
            await pendingLive?.value
            if !settings.dictationEnabled { await models.stop() }
            if token == current { phase = .idle; stopTask = nil }
        }
    }

    func prepareForTermination() {
        enableTask?.cancel()
        cancel()
        audioDucker.restoreImmediately()
        models.prepareForTermination()
    }

    private func reset(cancelTranscription: Bool = true) {
        token = UUID()
        if cancelTranscription { transcriptionTask?.cancel() }
        startTask = nil
        transcriptionTask = nil
        live?.task?.cancel()
        live = nil
        phase = .idle
        target = nil
        field = nil
        panel.close()
        audioDucker.end()
    }

    // MARK: - Typing while speaking

    private static let livePassInterval = Duration.milliseconds(500)
    /// Under the model's 15 s window, so a pass never splits its audio on its own.
    private static let liveSegmentSamples = DictationWire.sampleRate * 12

    private func startLiveTyping(token current: UUID) {
        let session = LiveTyping(context: DictationInsertionContext.read(in: target))
        live = session
        session.task = Task { [weak self] in await self?.transcribeWhileListening(session, token: current) }
    }

    private func transcribeWhileListening(_ session: LiveTyping, token current: UUID) async {
        let model = settings.dictationModel
        let minimum = DictationWire.sampleRate / 2
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.livePassInterval)
            guard !Task.isCancelled, token == current else { return }
            let samples = capture.samples(from: session.start)
            guard samples.count >= minimum else { continue }
            let cut =
                samples.count >= Self.liveSegmentSamples
                ? DictationAudioChunks.ranges(in: samples, maximum: Self.liveSegmentSamples)[0].upperBound : nil
            let audio = cut.map { Array(samples[..<$0]) } ?? samples
            // Unstructured, so finishing early waits for the pass instead of killing the helper.
            let pass = Task { try await models.transcribe(audio, model: model, language: nil) }
            let text: String
            do { text = try await pass.value } catch {
                guard token == current else { return }
                cancel()
                showMessage(error.localizedDescription, .danger)
                return
            }
            guard !Task.isCancelled, token == current else { return }
            if let cut {
                type(session.transcript.close(text, carriesOver: true), in: session, token: current)
                session.start += cut
                panel.state.preview = ""
                continue
            }
            let step = session.transcript.update(text)
            type(step.typed, in: session, token: current)
            panel.state.preview = step.pending.joined(separator: " ")
            if step.isSettled {
                _ = session.transcript.close(text, carriesOver: false)
                session.start += DictationAudioChunks.quietPoint(
                    in: samples, within: (samples.count - minimum)..<samples.count)
            }
        }
    }

    private func finishLiveTyping(_ session: LiveTyping, samples: [Float], token current: UUID) async {
        session.task?.cancel()
        await session.task?.value
        guard token == current else { return }
        let remaining = Array(samples.dropFirst(session.start))
        var words: [String] = []
        if remaining.count >= 1_600 {
            do {
                let text = try await models.transcribe(
                    remaining, model: settings.dictationModel, language: nil)
                words = session.transcript.close(text, carriesOver: false)
            } catch {
                guard token == current else { return }
                reset(cancelTranscription: false)
                showMessage(error.localizedDescription, .danger)
                return
            }
            guard token == current else { return }
        } else if session.typed.isEmpty {
            reset(cancelTranscription: false)
            showMessage("No speech was recorded", .danger)
            return
        }
        panel.close()
        type(words, in: session, token: current)
        let complete = { [weak self] in
            guard let self, token == current else { return }
            let destination = field == nil ? settings.dictationDestination : .paste
            let text = session.typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if destination.copies, !text.isEmpty { Paster.copyPlainText(text) }
            reset(cancelTranscription: false)
        }
        if session.deliveries == 0 { complete() } else { session.onDrained = complete }
    }

    private func type(_ words: [String], in session: LiveTyping, token current: UUID) {
        guard !words.isEmpty else { return }
        let text = DictationTextFormatter.format(
            words.joined(separator: " "),
            context: .continuing(session.context, after: session.typed),
            adaptCapitalization: settings.dictationAdaptsCapitalization)
        guard !text.isEmpty else { return }
        session.typed += text
        session.deliveries += 1
        injector.deliver(
            InjectedText(text), target: target, expectedKeyword: nil,
            keywordLength: 0, automaticGeneration: nil,
            isValid: { [weak self] in self?.token == current },
            onDelivered: { session.settle() },
            onFailed: { [weak self] in
                session.settle()
                guard let self, token == current else { return }
                cancel()
                showMessage("Couldn't type dictation into this app", .danger)
            })
    }
}

/// One live session: what was typed, where the untyped audio starts, and the queued insertions.
@MainActor
private final class LiveTyping {
    let context: DictationTextFormatter.Context?
    var transcript = DictationLiveTranscript()
    var start = 0
    var typed = ""
    var task: Task<Void, Never>?
    var deliveries = 0
    var onDrained: (() -> Void)?

    init(context: DictationTextFormatter.Context?) { self.context = context }

    func settle() {
        deliveries -= 1
        guard deliveries == 0, let drained = onDrained else { return }
        onDrained = nil
        drained()
    }
}

/// Which editor a mic session belongs to, so only that field's button shows it running.
struct DictationField: Equatable {
    let editor: ObjectIdentifier
    var isTranscribing = false
}

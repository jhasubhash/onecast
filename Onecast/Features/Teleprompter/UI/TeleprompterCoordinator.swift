import AppKit
import SwiftUI

/// Owns the prompter: the script being drafted, the run through it, and the overlay showing it.
@MainActor
@Observable
final class TeleprompterCoordinator {
    /// The editor's text, kept on disk so the next session opens on the same script.
    var draft: String {
        didSet { saveDraft() }
    }
    private(set) var script = TeleprompterScript("")
    /// The word the speaker is on; fractional while Classic or Voice-Activated glides between words.
    private(set) var position: Double = 0
    private(set) var isRunning = false
    private(set) var isPaused = false
    private(set) var isSpeaking = false

    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private let listener = TeleprompterListener()
    @ObservationIgnored private var panel: TeleprompterPanel?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastHeard: [String] = []
    /// The furthest word speech recognition has placed the speaker at, while it is listening.
    @ObservationIgnored private var confirmed: Int?
    @ObservationIgnored private var lastVoice = Date.distantPast
    @ObservationIgnored private lazy var editor = AppWindowController(
        title: "Teleprompter", contentSize: CGSize(width: 560, height: 440), resizable: true,
        activation: core.activationPolicy, closesOnEscape: true)

    private static let voiceThreshold: Float = 0.38
    /// Speech trails off between words; this long a gap still counts as speaking.
    private static let voiceHangover: TimeInterval = 0.45
    private static let frame: Duration = .milliseconds(33)
    /// How far Voice-Activated's pace may run past the last word recognized, before it waits.
    private static let paceLead = 6

    init(core: AppCore) {
        self.core = core
        draft = (try? String(contentsOf: Self.draftFile, encoding: .utf8)) ?? ""
        listener.onHeard = { [weak self] in self?.heard($0) }
        listener.onLevel = { [weak self] in self?.level($0) }
    }

    var settings: AppSettings { core.settings }

    var currentWord: Int { min(Int(position), script.words.count) }

    func applyEnabled() {
        core.appIndex.setCommandsVisible(
            [.openTeleprompter, .teleprompterSelection, .pauseTeleprompter], settings.teleprompterEnabled)
        guard !settings.teleprompterEnabled else { return }
        stop()
        editor.close()
    }

    func openEditor() {
        editor.show { TeleprompterEditorView(coordinator: self).environment(self.core.settings) }
    }

    /// Reads the selection the way Quick Actions do, then prompts it straight away.
    func promptSelection(in app: NSRunningApplication?) {
        Task {
            do {
                let text = try await QuickActionRunner.selection(in: app, using: core.textInjector)
                await start(text)
            } catch {
                core.showMessage(error.localizedDescription, tone: .danger)
            }
        }
    }

    func startDraft() {
        editor.close()
        Task { await start(draft) }
    }

    func start(_ text: String) async {
        let script = TeleprompterScript(text)
        guard !script.isEmpty else {
            core.showMessage("The script is empty", tone: .danger)
            return
        }
        stop()
        let mode = settings.teleprompterMode
        if mode.usesMicrophone {
            // Voice-Activated also follows the words where it may, but keeps its pace where it may not.
            var transcribing = true
            switch await TeleprompterListener.authorize(transcribing: true) {
            case nil: break
            case .speechDenied? where mode == .voiceActivated: transcribing = false
            case let failure?:
                core.showMessage(failure.message, tone: .danger)
                return
            }
            if let failure = listener.start(transcribing: transcribing) {
                core.showMessage(failure.message, tone: .danger)
                return
            }
            confirmed = transcribing ? 0 : nil
        } else {
            confirmed = nil
        }
        self.script = script
        position = Double(script.nextSpoken(from: 0))
        lastHeard = []
        isPaused = false
        isRunning = true
        present()
        if mode != .wordTracking { startTicker() }
    }

    func togglePause() {
        guard isRunning else { return }
        isPaused.toggle()
    }

    func restart() {
        guard isRunning else { return }
        position = Double(script.nextSpoken(from: 0))
        lastHeard = []
        if confirmed != nil { confirmed = 0 }
        isPaused = false
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        listener.stop()
        isRunning = false
        isSpeaking = false
        guard let closing = panel else { return }
        panel = nil
        closing.onScroll = nil
        closing.fadeOut(duration: Theme.Duration.exit)
    }

    /// The wheel catches up or backs up by whole words, in any mode.
    func scroll(by lines: CGFloat) {
        guard isRunning, !script.isEmpty else { return }
        let moved = position - Double(lines) * 2
        position = min(max(moved, 0), Double(script.words.count - 1))
        lastHeard = []
        if confirmed != nil { confirmed = currentWord }
    }

    /// Word Tracking moves only on words; Voice-Activated's pace is pulled forward to them, never back.
    private func heard(_ words: [String]) {
        guard isRunning, !isPaused, settings.teleprompterMode.usesMicrophone, words != lastHeard else {
            return
        }
        lastHeard = words
        // From the last word heard, not the pace's guess, so a pace that ran ahead still finds the speaker.
        let from = min(confirmed ?? currentWord, currentWord)
        let next = TeleprompterAligner.advance(from: from, heard: words, in: script)
        if next > from { confirmed = next }
        if next > currentWord { position = Double(next) }
        finishIfDone()
    }

    private func level(_ level: Float) {
        guard isRunning else { return }
        if level >= Self.voiceThreshold { lastVoice = .now }
        let speaking = Date.now.timeIntervalSince(lastVoice) < Self.voiceHangover
        if speaking != isSpeaking { isSpeaking = speaking }
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            var last = ContinuousClock.now
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.frame)
                let now = ContinuousClock.now
                let elapsed = now - last
                last = now
                self?.tick(seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
            }
        }
    }

    private func tick(seconds: Double) {
        guard isRunning, !isPaused else { return }
        if settings.teleprompterMode == .voiceActivated, !isSpeaking { return }
        var next = position + Double(settings.teleprompterSpeed) / 60 * seconds
        if let confirmed { next = min(next, Double(confirmed + Self.paceLead)) }
        guard next > position else { return }
        position = next
        // Cues are read, not spoken, so the pace steps straight over them.
        let spoken = script.nextSpoken(from: Int(position))
        if spoken > Int(position) { position = Double(spoken) }
        finishIfDone()
    }

    /// The last word said, the prompter lingers a moment and then gets out of the way.
    private func finishIfDone() {
        guard script.nextSpoken(from: currentWord) >= script.words.count else { return }
        position = Double(script.words.count)
        ticker?.cancel()
        ticker = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, isRunning, currentWord >= script.words.count else { return }
            stop()
        }
    }

    private func present() {
        let placement = settings.teleprompterPlacement
        let screen = NSScreen.underCursor ?? NSScreen.main
        let inset = TeleprompterPanel.topInset(for: placement, on: screen)
        let size = TeleprompterPanel.size(
            for: placement, textSize: settings.teleprompterTextSize, topInset: inset)
        let hosting = NSHostingView(
            rootView: TeleprompterView(coordinator: self, placement: placement, topInset: inset))
        hosting.setFrameSize(size)
        let panel = TeleprompterPanel(content: hosting, placement: placement)
        panel.onScroll = { [weak self] in self?.scroll(by: $0) }
        self.panel = panel
        panel.place(on: screen)
        panel.fadeIn(duration: Theme.Duration.enter) { panel.orderFrontRegardless() }
    }

    private static var draftFile: URL {
        AppPaths.applicationSupport().appending(path: "Teleprompter", directoryHint: .isDirectory)
            .appending(path: "script.txt")
    }

    private func saveDraft() {
        let file = Self.draftFile
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? draft.write(to: file, atomically: true, encoding: .utf8)
    }
}

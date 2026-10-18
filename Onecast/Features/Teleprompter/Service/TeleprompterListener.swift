import AVFoundation
import Speech

/// The prompter's microphone: what was said, for Word Tracking, and how loudly, for Voice-Activated.
@MainActor
final class TeleprompterListener {
    enum Failure: Error, Sendable {
        case microphoneDenied
        case speechDenied
        case recognizerUnavailable
        case microphoneUnavailable

        var message: String {
            switch self {
            case .microphoneDenied: "Allow Onecast to use the microphone in System Settings"
            case .speechDenied: "Allow Onecast to use Speech Recognition in System Settings"
            case .recognizerUnavailable: "Speech recognition isn't available for your language"
            case .microphoneUnavailable: "Couldn't start the microphone"
            }
        }
    }

    /// The words of the latest transcript, oldest first.
    var onHeard: (([String]) -> Void)?
    /// Loudness from 0 (silence) to 1.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private let box = RequestBox()
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0
    private(set) var isRunning = false

    /// Asked from the gesture that starts the prompter, never on launch.
    nonisolated static func authorize(transcribing: Bool) async -> Failure? {
        guard await Permissions.requestMicrophoneAccess() else { return .microphoneDenied }
        guard transcribing else { return nil }
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        return status == .authorized ? nil : .speechDenied
    }

    func start(transcribing: Bool) -> Failure? {
        guard !isRunning else { return nil }
        if transcribing {
            guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
                recognizer.isAvailable
            else { return .recognizerUnavailable }
            self.recognizer = recognizer
            beginTask()
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return .microphoneUnavailable }
        input.installTap(
            onBus: 0, bufferSize: 1024, format: format,
            block: Self.tap(box: box) { [weak self] level in
                Task { @MainActor in self?.onLevel?(level) }
            })
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            return .microphoneUnavailable
        }
        isRunning = true
        return nil
    }

    func stop() {
        isRunning = false
        generation += 1
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        box.request?.endAudio()
        box.request = nil
        task?.cancel()
        task = nil
        recognizer = nil
    }

    /// A recognition task ends on a pause or its own time limit, so a fresh one takes over.
    private func beginTask() {
        guard let recognizer else { return }
        generation += 1
        let current = generation
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        box.request = request
        task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.results { [weak self] words, ended in
                Task { @MainActor in
                    guard let self, current == self.generation else { return }
                    if let words { self.onHeard?(words) }
                    guard ended else { return }
                    // A beat first, so a recognizer that fails at once cannot spin.
                    try? await Task.sleep(for: .milliseconds(300))
                    if self.isRunning, current == self.generation { self.beginTask() }
                }
            })
    }

    /// Built outside the main actor: the tap runs on the audio thread.
    nonisolated private static func tap(
        box: RequestBox, level: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            box.request?.append(buffer)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            var sum: Float = 0
            for index in 0..<Int(buffer.frameLength) { sum += samples[index] * samples[index] }
            let rms = (sum / Float(buffer.frameLength)).squareRoot()
            let decibels = 20 * log10(max(rms, 0.000_01))
            level(min(max((decibels + 60) / 60, 0), 1))
        }
    }

    nonisolated private static func results(
        _ deliver: @escaping @Sendable ([String]?, Bool) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void {
        { result, error in
            let words = result.map { $0.bestTranscription.segments.map(\.substring) }
            deliver(words, error != nil || result?.isFinal == true)
        }
    }
}

/// The live request, read from the audio thread; appending to it is safe from any thread.
private final class RequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SFSpeechAudioBufferRecognitionRequest?

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

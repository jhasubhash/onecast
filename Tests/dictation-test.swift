import Foundation

@main
struct DictationTest {
    static func main() {
        func check(_ actual: String, _ expected: String) {
            guard actual == expected else {
                print("Expected \(expected.debugDescription), got \(actual.debugDescription)")
                exit(1)
            }
        }

        typealias Context = DictationTextFormatter.Context
        check(DictationTextFormatter.format("  Hello. \n", context: nil), "Hello.")
        check(DictationTextFormatter.format("hello", context: Context(before: "", after: "")), "Hello")
        check(DictationTextFormatter.format("World", context: Context(before: "Hello", after: "")), " world")
        check(DictationTextFormatter.format("world", context: Context(before: "Hello.", after: "")), " World")
        check(DictationTextFormatter.format("hello", context: Context(before: "Wait. ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("hello", context: Context(before: "Wait\n  ", after: "")), "Hello")
        check(
            DictationTextFormatter.format("World", context: Context(before: "Hello ", after: "again")),
            "world ")
        check(DictationTextFormatter.format("hello", context: Context(before: "(", after: ")")), "hello")
        check(
            DictationTextFormatter.format("application", context: Context(before: "l’", after: "")),
            "application")
        check(
            DictationTextFormatter.format(
                "Onecast", context: Context(before: "Use", after: "again"),
                adaptCapitalization: false), " Onecast ")
        check(
            DictationTextFormatter.format(
                "world", context: Context(before: "Hello.", after: ""),
                adaptCapitalization: false), " world")
        check(
            DictationTextFormatter.format(
                "hello", context: Context(before: "", after: ""),
                adaptCapitalization: false), "hello")
        check(
            DictationTextFormatter.format(
                "World.", context: Context(before: "Hello ", after: ")"),
                adaptCapitalization: false), "World.")
        let document = "prefix. Text to replace suffix"
        check(
            DictationTextFormatter.format(
                "world",
                context: Context(
                    before: document.prefix(7), after: document.suffix(6))), " World ")

        typealias Step = DictationLiveTranscript.Step
        func step(_ actual: Step, _ typed: [String], _ pending: [String], settled: Bool = false) {
            guard actual == Step(typed: typed, pending: pending, isSettled: settled) else {
                print("Expected typed \(typed) pending \(pending) settled \(settled), got \(actual)")
                exit(1)
            }
        }
        var live = DictationLiveTranscript()
        step(live.update("Send the"), [], ["Send", "the"])
        step(live.update("Send the logs."), ["Send", "the"], ["logs."])
        step(live.update("Send the logs from"), [], ["logs", "from"])
        step(live.update("Send the logs from"), ["logs", "from"], [], settled: true)
        step(live.update("Send a log"), [], [])
        check(live.close("Send the log", carriesOver: true).description, "[]")
        check(live.committed.description, "1")
        step(live.update("from here"), [], ["here"])
        step(live.update("from here now"), ["here"], ["now"])
        check(live.close("from here now please", carriesOver: false).description, "[\"now\", \"please\"]")
        check(live.committed.description, "0")
        step(live.update("Ice cream"), [], ["Ice", "cream"])
        step(live.update("I scream"), [], ["I", "scream"])

        let base = Context(before: "Hello", after: "x")
        check(DictationTextFormatter.format("There", context: .continuing(base, after: "")), " there ")
        check(DictationTextFormatter.format("And", context: .continuing(base, after: " there ")), "and ")
        check(DictationTextFormatter.format("next", context: .continuing(base, after: " done. ")), "Next ")
        check(DictationTextFormatter.format("next", context: .continuing(base, after: " done.")), " Next ")
        check(DictationTextFormatter.format("Hi", context: .continuing(nil, after: "")), "Hi")
        check(DictationTextFormatter.format("World", context: .continuing(nil, after: "Hello")), " world")
        check(DictationModel.redux.folderName, "parakeet-redux")
        check(DictationModel.ultra.folderName, "parakeet-ultra")
        check(DictationModel.redux.title, "Parakeet · Redux")
        check(DictationModel.ultra.title, "Parakeet · Ultra")
        check(DictationIdleRelease.allCases.map(\.rawValue).description, "[0, 1, 2, 5, 10, 15, 20, 30, 60]")
        check(DictationIdleRelease.never.title, "Never")
        check(DictationIdleRelease.oneHour.title, "1 hour")
        check(DictationModel.qwenSmall.folderName, "qwen-0.6b")
        check(DictationModel.qwenLarge.folderName, "qwen-1.7b")
        for family in DictationModel.Family.allCases {
            guard DictationModel.allCases.contains(where: { $0.family == family }) else {
                fatalError("Every engine should expose at least one model")
            }
        }
        for model in DictationModel.allCases {
            guard !model.components.isEmpty, model.revision.count == 40,
                model.requiredFiles.isSuperset(of: model.components)
            else {
                fatalError("Model installation metadata is incomplete")
            }
            if let configuration = model.parakeetConfiguration {
                guard model.family == .parakeet, configuration.blankToken == 8192,
                    configuration.encoderUsesGPU == (model == .redux),
                    model.components.contains(configuration.joint + ".mlmodelc")
                else {
                    fatalError("Parakeet download and inference disagree")
                }
            } else if !model.isQwen {
                fatalError("Missing Parakeet decoding configuration")
            }
        }
        print("Dictation text formatting passed")
    }
}

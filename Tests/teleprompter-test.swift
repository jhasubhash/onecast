// Standalone test for the teleprompter's script and the speech follower, compiling the real sources.
import Foundation

@main
@MainActor
struct TeleprompterTests {
    static var failures = 0
    static var passes = 0

    static let speech = TeleprompterScript(
        "Good morning, everyone. [pause] Thanks for joining.\nToday we ship the new release of the app.")

    static func main() {
        splitsWordsWithKeys()
        cuesAreMarked()
        paragraphsBreak()
        followsWordByWord()
        stepsOverCues()
        catchesUpAfterASkip()
        oneCommonWordDoesNotLeapAhead()
        neverMovesBack()
        toleratesASlip()
        unrelatedSpeechStaysPut()

        print("\(passes)/\(passes + failures) passed")
        if failures > 0 { exit(1) }
    }

    static func index(of word: String) -> Int {
        speech.words.firstIndex { $0.key == word }!
    }

    static func splitsWordsWithKeys() {
        expect(speech.words.first?.text == "Good", "a word keeps its text as written")
        expect(speech.words[1].key == "morning", "the key drops punctuation and case")
    }

    static func cuesAreMarked() {
        expect(speech.words[3].isCue && speech.words[3].text == "[pause]", "a bracketed word is a cue")
        let long = TeleprompterScript("Hi [look at camera] there")
        expect(long.words.map(\.isCue) == [false, true, true, true, false], "a cue runs to its closing bracket")
    }

    static func paragraphsBreak() {
        expect(speech.words[index(of: "today")].breaksBefore, "a new line starts a paragraph")
        expect(!speech.words[1].breaksBefore, "words within a line do not")
    }

    static func followsWordByWord() {
        var position = 0
        position = TeleprompterAligner.advance(from: position, heard: ["Good"], in: speech)
        expect(position == 1, "saying the first word moves to the second")
        position = TeleprompterAligner.advance(from: position, heard: ["good", "morning"], in: speech)
        expect(position == 2, "each word said moves on by one")
    }

    static func stepsOverCues() {
        let position = TeleprompterAligner.advance(
            from: 0, heard: ["good", "morning", "everyone"], in: speech)
        expect(position == index(of: "thanks"), "a cue after the spoken word is stepped over")
    }

    static func catchesUpAfterASkip() {
        let position = TeleprompterAligner.advance(
            from: 0, heard: ["today", "we", "ship"], in: speech)
        expect(position == index(of: "the"), "a phrase further on catches the prompter up")
    }

    static func oneCommonWordDoesNotLeapAhead() {
        let position = TeleprompterAligner.advance(from: 0, heard: ["the"], in: speech)
        expect(position == 0, "a lone common word far ahead does not jump there")
    }

    static func neverMovesBack() {
        let later = index(of: "today")
        expect(
            TeleprompterAligner.advance(from: later, heard: ["good", "morning"], in: speech) == later,
            "a recognizer revisiting earlier words never drags the prompter back")
    }

    static func toleratesASlip() {
        expect(TeleprompterAligner.similar("releases", "release"), "a plural is the same word")
        expect(TeleprompterAligner.similar("joinin", "joining"), "one dropped letter still matches")
        expect(!TeleprompterAligner.similar("cat", "car"), "a short word must match exactly")
    }

    static func unrelatedSpeechStaysPut() {
        expect(
            TeleprompterAligner.advance(from: 0, heard: ["banana", "spaceship"], in: speech) == 0,
            "words not in the script move nothing")
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}

# Teleprompter

A script you read from while you talk, in the spirit of [Textream](https://github.com/f/textream).
**Open Teleprompter** opens an editor to paste or write the script and press Start (⌘↵);
**Teleprompt Selected Text** prompts whatever is selected in the front app, read the way Quick Actions
read a selection; **Pause or Resume Teleprompter** is the one to bind to a shortcut. All three take
aliases and hotkeys like any other command.

## Guidance modes

| Mode | What moves the script | Microphone |
|---|---|---|
| **Word Tracking** (default) | Apple speech recognition: each word lights up as it is said | Yes, plus Speech Recognition |
| **Classic** | A steady pace, 60–300 words per minute | No |
| **Voice-Activated** | That pace, only while a voice is heard, kept in step with the words recognized | Yes, plus Speech Recognition where allowed |

The scroll wheel or trackpad moves the script back or forward in any mode, so a speaker who skipped
ahead or went back can resync.

## Invariants

- **The audience never sees the script.** `TeleprompterPanel` sets `sharingType = .none`, so screen
  shares, recordings and screenshots leave it out. It never becomes key, so the presented app keeps
  focus and keyboard.
- **Nothing listens until a script starts.** The microphone and Speech Recognition prompts come from
  the Start gesture (`TeleprompterListener.authorize`), never from launch or Settings, and the audio
  engine stops with the overlay. Classic never touches the microphone.
- **The follower never moves back.** `TeleprompterAligner.advance` matches the latest heard words, as a
  phrase read backwards from the newest, against the next 24 words of the script. A match within two
  words of the current one needs one word; further ahead needs two, so a lone common word ("the")
  can't leap the prompter forward. A recognizer revising an earlier guess never drags it back. Words
  match equal, or one edit apart / as a prefix once both are four letters or longer.
- **Voice-Activated keeps pace with the speaker, both ways.** Where Speech Recognition is allowed it
  listens for words too: a recognized word ahead pulls the pace forward to it, and the pace never runs
  more than six words past the last word recognized, so a slow reader is waited for. Without Speech
  Recognition it falls back to the plain pace while a voice is heard.
- **Cues are shown, never spoken.** Text in `[square brackets]` is dimmed and italic; the follower and
  the steady pace both step straight over it.
- **Recognition restarts itself.** A recognition task ends on a pause or its time limit; the listener
  begins a fresh one 300 ms later while the prompter runs, and stale callbacks are dropped by a
  generation counter. On-device recognition is required wherever the recognizer supports it.
- **Finishing closes it.** Two seconds after the last word, the overlay fades out and the microphone stops.

## Placement

**Below the Notch** hangs a black pill from the top edge of the screen under the pointer, its text
starting below the notch (or the menu bar on a screen without one). **Floating Window** is a glass
panel below the menu bar that drags anywhere. Hovering shows the controls: restart, pause/resume and
close, with the word count and, in microphone modes, whether a voice is heard.

## How it is put together

| Layer | Pieces |
|---|---|
| Model | `TeleprompterScript` (words, keys, cues, paragraphs), `TeleprompterAligner`, `TeleprompterOptions` (mode, placement, highlight, pace) |
| Service | `TeleprompterListener`: `AVAudioEngine` tap feeding `SFSpeechAudioBufferRecognitionRequest` and a loudness level |
| UI | `TeleprompterCoordinator` (lazy on `AppCore`), `TeleprompterPanel`, `TeleprompterView` (a wrapping word layout scrolled to the reading line), `TeleprompterEditorView` |
| Settings | `TeleprompterSettingsView`: enable, mode, speed, position, text size, highlight color, commands |

The draft lives in `~/Library/Application Support/<bundle id>/Teleprompter/script.txt`, so the editor
reopens on the last script. Settings are in backup and `settings.json` under `teleprompter.*`.

## Tests

`Tests/teleprompter-test.swift` covers parsing (keys, cues, paragraphs) and the follower: word by word,
stepping over cues, catching up after a skip, ignoring a lone common word ahead, never moving back,
tolerating slips, and ignoring unrelated speech.

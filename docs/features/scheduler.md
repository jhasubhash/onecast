# Scheduler

The scheduler runs a **shell script** or posts a **notification** on a recurring rule — once, on an
interval, or daily / weekly / monthly — and catches up on fires missed while the app or the Mac was
Tasks are created, edited and deleted in **Settings → Scheduler** or from the launcher's own
in-palette editor, run automatically when due, and can also be run on demand from the launcher or a
global shortcut.

The pane carries the feature switch — off out of the box — and its launcher-visibility companion,
both in `AppSettings` and (with one deliberate exception, [below](#settings-and-backup)) in settings
backups. Switching the feature off cancels the pending wake and makes `SchedulerCoordinator.runTask`
refuse to run anything; the stored tasks and their per-task anchors stay put, so re-enabling resumes
without re-firing what was skipped.

## Invariants

- **`Model/` stays free of AppKit and SwiftUI.** `ScheduledTask`, `ScheduleEngine`,
  `NaturalDateParser` and `ScheduleFormatter` are Foundation-only and take the clock/calendar as
  injected parameters — `scheduler-test` compiles them, so this is enforced by compilation.
- **A task owns its own `lastFired` anchor.** Every fire records the *occurrence's* date via
  `store.markFired(id:at:)`, not the wall clock, and the next fire is computed from that anchor.
  Editing a schedule never double-fires and never drifts, because the anchor is the only source of
  "what has this task already done".
- **A disabled task is inert at the engine level.** `ScheduleEngine.nextFireDate` returns `nil` for a
  disabled task, so it never contributes to the wake target and `fireDue` never runs it — the
  `disabledTaskNeverFires` case in `scheduler-test` pins this.
- **Catch-up is bounded.** `SchedulerCoordinator.catchUpCap` (25) caps how many missed occurrences a
  single resume replays for one task, so a Mac that slept for a month cannot unleash a flood.
- **One pending wake for the whole set.** The coordinator holds a single `Task` timer, armed to the
  earliest `nextFire` across all tasks; any change to the task set or the feature switch cancels and
  re-arms it. There is never a timer per task.
- **A notification is a Onecast panel, never `NSAlert` or `NSUserNotification`.** The
  `Notifications/` module posts through `NotificationPresenter` onto a per-corner stacking
  `NotificationPanel`, honouring the app-wide "Onecast presents its own dialogs" rule.
- **The AI tool schedules notifications only.** `SchedulerAITool` (`scheduler__create_reminder`) can
  post a *future notification* but can never register a shell script — untrusted model output must not
  gain unattended code execution.
- **A reminder reaches another app only with consent.** Apple Reminders and Things are each off
  until switched on in **Settings → Scheduler → Reminder apps** (`schedulerReminderApps`, never in a
  backup), and Apple Reminders also needs macOS's own Reminders grant. A phrase naming an app that
  is off is refused with a HUD, never quietly scheduled in Onecast instead.

## Model and persistence

`ScheduledTask` is `Codable`/`Identifiable`: an id, name, `isEnabled`, a `ScheduleRule`, a
`ScheduledAction`, a `CatchUpPolicy`, its `lastFired` anchor and `createdAt`.

- `ScheduleRule` — `once(date:)`, `interval(seconds:)`, `daily(hour:minute:)`,
  `weekly(weekdays:hour:minute:)` (Calendar weekday integers, Sunday = 1) and `monthly(day:hour:minute:)`.
- `ScheduledAction` — `runScript(ScriptSpec)` or `postNotification(NotificationSpec)`.
- `CatchUpPolicy` — `skip` (advance the anchor, fire nothing), `fireOnceOnResume` (fire once, advance
  to the last missed) or `fireEach` (replay every missed occurrence up to the cap).

`ScheduledTaskStore` (`@MainActor @Observable`) is the single owner. It persists the array as JSON in
`UserDefaults` under `scheduledTasks`; a decode failure drops to an empty list rather than losing the
whole app's defaults. Its `onChange` hook is what the coordinator subscribes to, so any edit
reschedules and re-projects launcher rows.

`ScheduleEngine` is the pure math: `nextFireDate(for:after:calendar:)` gives the first occurrence a
task owes past an anchor, and `missedOccurrences(for:since:until:calendar:cap:)` enumerates the
catch-up set. `NaturalDateParser` reads a time out of a phrase — relative durations ("in 20 minutes")
first, since `NSDataDetector` resolves only the absolute forms ("tomorrow 9am") — and each `Match`
carries the span it matched, so a caller can lift the time out of a sentence and keep the rest.
`ReminderPhraseParser` builds on it: it turns a whole launcher phrase into a `ParsedReminder`
(title + `ScheduleRule`) by reading a recurrence word and a time, then cleaning the words left over
into a title. `ScheduledTask.notification(title:body:rule:now:)` is the shared builder both it and the
AI tool use, and `ScheduleFormatter.summary(of:)` renders the human line shown on each row.

## Firing and catch-up

`SchedulerCoordinator.arm()` runs on `AppCore.start()` and whenever the switch or task set changes.
When enabled it first `catchUp()`s, then `reschedule()`s the single wake to the earliest `nextFire`.
On wake, `fireDue()` fires every task whose next occurrence is within a 0.5 s tolerance of now —
recording each via `markFired` before running it — then re-arms. Off cancels the timer.

`catchUp()` walks each enabled task from its own `lastFired ?? createdAt`, asks the engine for the
missed occurrences, and applies the task's `CatchUpPolicy`. Because the anchor is per task, a task
added while others were overdue only ever replays *its* history.

`perform(_:name:)` dispatches the action: a notification goes straight to `NotificationPresenter`; a
script runs through `ShellCommandRunner.run(loadingShellEnvironment: true, …)` off the main actor,
and — if the task set `notifyOnFinish` — a completion toast reports the last output line or a failure.

## Launcher and shortcut

An enabled task projects an `AppEntry` of `kind: .scheduledTask` (url `onecast://scheduled-task/<uuid>`),
gated by both the feature switch and `schedulerShowInLauncher`. Selecting the row, or firing its
optional global shortcut (`HotKeyAction.scheduledTask`), calls `runTask(id:)`, which runs the action
immediately without touching the schedule or the anchor. `VisibilityStore` carries a matching
`.scheduledTask` category so the section can be toggled like any other.

The row's **⌘K actions** carry *Edit* and *Delete* — both open through `SchedulerEditorCoordinator`,
not Settings: edit opens the in-palette `SchedulerEditorScreen` (palette mode `.schedulerEditor`), a
two-column form sized to fit the fixed launcher panel without scrolling; delete confirms through the
app's own `DialogController` (never an `NSAlert`). Creating one is the `createScheduledTask` command
(`Create Scheduled Task`), an owned command of the Scheduler pane gated by the same two flags, so it also
carries an alias and optional shortcut in **Settings → Scheduler → Commands**.

The in-palette editor and the Scheduler pane's `SchedulerTaskEditorSheet` render the *same*
`SchedulerTaskControls`, both bound to a shared `ScheduledTaskDraft`, so a restyle lands on both
surfaces; only the arrangement and the actions chrome differ. The palette form owns no buttons of its
own — Save/Add rides the launcher's shared footer `ActionBar` on ↵, and Delete sits under ⌘K while
editing — whereas the sheet keeps its own Cancel/Save. Neither reads `@Environment(\.dismiss)`;
dismissal is injected.

## AI tool

Whenever the feature is on, `AIChatCoordinator` offers `SchedulerAITool` to the model alongside the
MCP tools. It creates a notification-only task from a natural-language time, so the assistant can set
a reminder — but, by the [invariant above](#invariants), it can never schedule a script.

The tool reaches every route that runs host tools, not just the HTTP ones. An API connection hands
each call back through `AIToolLoopProvider`; the on-device Apple Intelligence model instead runs it
in-process, so `toolAware` arms `AppleIntelligenceProvider.executingHostTools`.
`AppleIntelligenceHostTool` bridges the `AITool` onto a `FoundationModels.Tool` — its
`AppleIntelligenceToolSchema` turns the JSON-Schema parameters into a `GenerationSchema`, and each
call reports a `.toolCall`/`.toolResult` pair into the same stream a loop route would.

## Reminder fallback

Whenever the feature is on, the launcher offers a **Schedule a Reminder** fallback
(`Fallback.Builtin.scheduleReminder`, wearing the *Create Scheduled Task* name and clock glyph). ↵ on
its "Use “<query>” with…" row runs `SchedulerEditorCoordinator.scheduleFromPhrase`, which parses the
typed phrase and posts a notification-only task with no form — so, like the AI tool, it can never
register a script.

`scheduleFromPhrase` tries the deterministic `ReminderPhraseParser` first: it is Foundation-only,
instant, and works on every Mac with no AI, covering "remind me to book the ticket in next 20 min",
"drink water every day at 8am" and the like. The phrase goes to `ReminderPhraseModel` instead when
the parser finds no time, or when it asks to send the reminder somewhere ("add it …") that no cue
could name (`asksForATarget`). The model reads the whole phrase, typos included, into a
`ReminderReading` — title, time, repeat and where it goes — via guided generation (`@Generable`); its
`namesATime` field comes first, so a phrase with no time is never given an invented one. A time or an
app the parser did find outranks the model's. With no model, or no usable answer, the parser's own
reading stands, and a phrase with no time for Onecast surfaces an error rather than a guess.

When the typed phrase reads as a reminder request — `IntentClassifier.standard` scores it `.reminder`
off a keyword like "remind me" or "notify me", before any time is even typed — `FallbackCoordinator`
asks `Fallback.prioritised` to float this row to the top of the fallback list so ↵ lands on scheduling.
Intent classification is a shared `Features/Intent/` concern, not the scheduler's: every fallback maps
to a `QueryIntent` through `Fallback.Builtin.intent`, so search, shell and AI rows promote the same
way. It is a per-query reorder of the displayed rows only; the stored fallback order is untouched.

A colour instruction rides along: `ReminderPhraseParser.splittingTint` lifts "color it green",
"make it red", "…in blue" at the end, "colour: grey" or "a purple reminder" out of the phrase before
either parser sees it, so the title stays "Drink water" and the time is untouched. It needs a cue — a
bare colour word ("buy green tea") stays in the title. The AI tool takes the same choice as an
optional `color` argument.

**A phrase can name where it goes.** `ReminderPhraseParser.splittingTargets` lifts "…, add it to
Apple Reminders", "put this in my Reminders", "in the Things app" or a list — "add it to Things and
Apple Reminders and Onecast" — out first, so neither parser sees it. The cue is loose, since these are
typed fast ("add it tp thngs"), but like a colour it needs one: "sort the things in the attic" keeps
its words. With no cue it is Onecast's alone; named, it goes to exactly the `ReminderTargets` listed.
Every target is checked before any is written — its app switched on, a time where Onecast needs one,
a rule the app can hold — so a phrase is never half-kept; only an app's own save can still fail, and
the HUD then names what was kept and what was not. `ReminderAppExporter` writes Apple Reminders through
EventKit to the default list, with a due date, an alarm and a daily, weekly or monthly recurrence, and
Things through `things:///add?title=…&when=<date>@<time>` (`ThingsURL`, the time rounded up to the
minute), opened without activating Things. With no time, both keep an undated to-do.
`ReminderApp.refusal` turns down what an app cannot hold: every-N-minutes repeats for Reminders, and any repeat for
Things, whose URL scheme cannot make one. The AI tool takes the same choice as an optional `app`
argument, once per app, handed a `ReminderHandOff` closure so it stays compilable without EventKit.

## Settings and backup

`schedulerEnabled`, `schedulerShowInLauncher`, `schedulerPlaysSound` and `schedulerReminderApps` live in
`AppSettings`/`AppSettingsKey`. `schedulerPlaysSound` (on by default; **Settings → Scheduler →
Notifications → Play a sound**) chimes the system "Glass" sound when a scheduled notification or a
script's finish toast appears. `schedulerShowInLauncher` and `schedulerPlaysSound` are backed up like
every other preference. `schedulerEnabled` is in `SettingsBackupCoverage.deliberatelyExcluded`: it
doubles as consent to run a script or action unattended, so — like `snippetsEnabled`,
`calendarEnabled` and `cameraPreview` — an imported backup must never be able to arm the machine to
fire on a timer by itself. `schedulerReminderApps` is excluded too: it is consent to write to another
app's data. The Reminders grant also shows in **Settings → Permissions**, beside Calendars.

## Notifications module

`Features/Notifications/` is the surface the scheduler (and the AI tool) post to, but it owns nothing
scheduler-specific. `NotificationSpec` describes one notification (title, body, `style`, `corner`,
`dwell`, `actions`, `tint`); `NotificationPresenter` stacks live cards per screen corner on a floating
`NotificationPanel`; `NotificationPlacement` resolves the corner geometry; `NotificationCardView`
draws one. Nothing here uses `NSAlert` or a system notification. `post(_:playsSound:)` takes the
sound flag from the caller, so the module reads no scheduler setting. Cards anchor to
`NSScreen.primary` (the menu-bar display), never `NSScreen.main` — for an accessory app that follows
whichever display last held a key window, so cards landed on a secondary monitor.

**Colour.** `NotificationTint` is a fixed palette (blue, purple, pink, red, orange, yellow, green,
teal, gray), not a free colour: each stays legible on the glass card in both appearances, and
`init(word:)` folds spoken synonyms ("grey", "navy", "turquoise") onto it. A tinted card paints the
colour as its own background; `NotificationPalette` derives every other colour on it — text, icon
well, close and action buttons, edge — from one ink that `NotificationContrast` picks against the tint
*as the current appearance resolves it*: white whenever it clears WCAG's 3:1 floor for bold text and
UI glyphs, else black, so blue, red, purple and pink take white and yellow, green and orange take dark.
`tint` is optional and nil draws the neutral card, so a task saved before colour existed decodes
unchanged. The editor's **Color** swatches set it for a notification task; in the palette form they
sit in the left column, the only one with room below the fixed panel height.

## Manual checks

`scheduler-test` covers the engine math exhaustively — every rule shape, DST boundaries, and the
natural-date parser — but the live coordinator → notification path and the Settings / launcher
surfaces are driven by hand per [UI_TESTS.md](../../custom_docs/UI_TESTS.md): seed a task due shortly,
confirm the Scheduler pane lists it, the launcher shows the row, and the notification fires on time.

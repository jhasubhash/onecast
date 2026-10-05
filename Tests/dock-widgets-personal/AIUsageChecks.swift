import Foundation

@MainActor
enum AIUsageChecks {
    private static let t = DockWidgetsPersonalTests.self

    static func run() {
        timestamps()
        claudeLines()
        claudeDeduplication()
        codexTotals()
        ranges()
        bucketing()
        limitWindows()
        resetPhrases()
        formatting()
        settingsAndContent()
        scanner()
        copilotQuota()
        claudeUsage()
    }

    // MARK: - Copilot

    /// The shape `copilot_internal/user` returns: unlimited quotas carry no meter, premium leads.
    private static func copilotQuota() {
        let body = #"""
            {"copilot_plan":"business","quota_reset_date":"2026-11-01",
             "quota_reset_date_utc":"2026-11-01T00:00:00.000Z",
             "quota_snapshots":{
               "chat":{"unlimited":true,"percent_remaining":100.0,"remaining":0,"entitlement":0},
               "completions":{"unlimited":false,"percent_remaining":40,"remaining":800,"entitlement":2000},
               "premium_interactions":{"unlimited":false,"percent_remaining":75.7,
                 "remaining":302940,"entitlement":400000}}}
            """#
        guard let quota = PersonalCopilotQuota.parse(Data(body.utf8)) else {
            return t.expect(false, "a Copilot quota response parses")
        }
        t.expect(quota.plan == "Business", "the plan reads capitalised")
        t.expect(
            quota.buckets.map(\.id) == ["premium_interactions", "completions"],
            "unlimited quotas are dropped and premium requests come first")
        t.expect(quota.buckets.first?.title == "Premium requests", "premium requests are named")
        t.expect(quota.buckets.first?.usedPercent == 24, "75.7% left reads as 24% used")
        t.expect(quota.buckets.last?.usedPercent == 60, "an integer percent reads too")
        t.expect(
            quota.resetsAt == date("2026-11-01T00:00:00.000Z"), "the exact UTC reset instant is used")

        let dateOnly = #"{"quota_reset_date":"2026-12-01","quota_snapshots":{}}"#
        let plain = PersonalCopilotQuota.parse(Data(dateOnly.utf8))
        t.expect(
            plain?.resetsAt == date("2026-12-01T00:00:00Z") && plain?.buckets.isEmpty == true
                && plain?.plan == nil,
            "a bare reset date reads as UTC midnight, and no snapshots means nothing metered")
        t.expect(
            PersonalCopilotQuota.parse(Data(#"{"message":"Not Found"}"#.utf8)) == nil,
            "an answer without quota snapshots is not a quota")
        let over = #"{"quota_snapshots":{"x_y":{"percent_remaining":-5}}}"#
        let clamped = PersonalCopilotQuota.parse(Data(over.utf8))?.buckets.first
        t.expect(
            clamped?.usedPercent == 100 && clamped?.title == "X Y",
            "an overdrawn quota reads fully used and an unknown id is titled from itself")

        let report = quota.report
        t.expect(
            report.plan == "Business" && report.windows.map(\.usedPercent) == [24, 60]
                && report.windows.allSatisfy { $0.resetsAt == quota.resetsAt && $0.durationMinutes == nil },
            "a quota becomes a report whose windows share the monthly reset")
    }

    /// Anthropic's `api/oauth/usage` shape, and Claude Code's keychain sign-in.
    private static func claudeUsage() {
        let body = #"""
            {"five_hour":{"utilization":33.0,"resets_at":"2026-04-11T07:00:00.528743+00:00"},
             "seven_day":{"utilization":13,"resets_at":"2026-04-17T00:59:59.951713+00:00"},
             "seven_day_opus":null,
             "seven_day_sonnet":{"utilization":120.0,"resets_at":null},
             "extra_usage":{"is_enabled":false}}
            """#
        guard let report = PersonalClaudeUsage.report(Data(body.utf8), plan: "max") else {
            return t.expect(false, "a Claude usage response parses")
        }
        t.expect(report.plan == "Max", "the plan reads capitalised")
        t.expect(
            report.windows.map(\.id) == ["five_hour", "seven_day", "seven_day_sonnet"],
            "session and week come first; a null per-model week is left out")
        t.expect(
            report.windows.map(\.usedPercent) == [33, 13, 100],
            "utilization reads as percent used, held to 100")
        t.expect(
            report.windows.map(\.durationMinutes) == [300, 10_080, nil],
            "the session and week name their length; a per-model week keeps its own title")
        t.expect(
            report.windows[0].resetsAt == date("2026-04-11T07:00:00.528Z"),
            "a reset with microseconds and an offset parses")
        t.expect(report.windows[2].resetsAt == nil, "a null reset stays unknown")
        t.expect(
            PersonalClaudeUsage.report(Data(#"{"error":"x"}"#.utf8), plan: nil) == nil,
            "an answer with no windows is not a report")

        let stored = #"""
            {"claudeAiOauth":{"accessToken":"tok","refreshToken":"r","expiresAt":1760000000000,
             "subscriptionType":"enterprise","scopes":["user:inference"]}}
            """#
        let credentials = PersonalClaudeCredentials.parse(Data(stored.utf8))
        t.expect(
            credentials?.accessToken == "tok" && credentials?.subscription == "enterprise",
            "the keychain sign-in reads its token and plan")
        let expiry = Date(timeIntervalSince1970: 1_760_000_000)
        t.expect(
            credentials?.isExpired(now: expiry.addingTimeInterval(-120)) == false
                && credentials?.isExpired(now: expiry.addingTimeInterval(-30)) == true,
            "a sign-in counts as expired a minute before its stated end")
        t.expect(
            PersonalClaudeCredentials.parse(Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil,
            "an empty token is no sign-in")
    }

    // MARK: - Fixtures

    private static func utc() -> Calendar { calendar("UTC") }

    private static func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    private static func date(_ iso: String) -> Date {
        Date(timeIntervalSince1970: PersonalAIUsageTimestamp.parse(iso) ?? .nan)
    }

    private static let standardUsage =
        #"{"input_tokens":2,"cache_creation_input_tokens":20275,"cache_read_input_tokens":12204,"output_tokens":508}"#

    private static func claude(
        id: String? = "msg_1", request: String? = "req_1", time: String? = "2026-10-01T03:52:47.057Z",
        type: String? = "assistant", role: String? = "assistant", usage: String? = standardUsage
    ) -> Data {
        var fields: [String] = []
        if let type { fields.append(#""type":"\#(type)""#) }
        if let time { fields.append(#""timestamp":"\#(time)""#) }
        var message: [String] = [#""type":"message""#]
        if let role { message.append(#""role":"\#(role)""#) }
        if let id { message.append(#""id":"\#(id)""#) }
        if let usage { message.append(#""usage":\#(usage)"#) }
        fields.append(#""message":{\#(message.joined(separator: ","))}"#)
        if let request { fields.append(#""requestId":"\#(request)""#) }
        return Data("{\(fields.joined(separator: ","))}".utf8)
    }

    private static func claudeUsage(_ input: Int, _ output: Int) -> String {
        #"{"input_tokens":\#(input),"output_tokens":\#(output)}"#
    }

    private static func codex(
        _ time: String, input: Int, cached: Int = 0, output: Int, type: String = "token_count"
    ) -> Data {
        let usage =
            #"{"input_tokens":\#(input),"cached_input_tokens":\#(cached),"#
            + #""output_tokens":\#(output),"total_tokens":\#(input + output)}"#
        let head = #"{"timestamp":"\#(time)","type":"event_msg","#
        let body = #""payload":{"type":"\#(type)","info":{"total_token_usage":\#(usage),"#
        return Data(
            (head + body + #""last_token_usage":\#(usage)},"rate_limits":null}}"#).utf8)
    }

    private static func line(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - Timestamps

    private static func timestamps() {
        t.expect(
            PersonalAIUsageTimestamp.parse("2026-10-01T03:52:47Z") == 1_790_826_767,
            "a Z timestamp is its UTC epoch")
        let fractional = PersonalAIUsageTimestamp.parse("2026-10-01T03:52:47.057Z") ?? .nan
        t.expect(abs(fractional - 1_790_826_767.057) < 0.0005, "milliseconds are kept")
        t.expect(
            PersonalAIUsageTimestamp.parse("1970-01-01T00:00:00Z") == 0, "the epoch is zero")
        t.expect(
            PersonalAIUsageTimestamp.parse("2024-02-29T23:59:59Z") == 1_709_251_199,
            "a leap day parses")
        t.expect(
            PersonalAIUsageTimestamp.parse("2000-03-01T00:00:00Z") == 951_868_800,
            "the day after a century leap day parses")
        t.expect(
            PersonalAIUsageTimestamp.parse("2026-10-01T09:22:47+05:30")
                == PersonalAIUsageTimestamp.parse("2026-10-01T03:52:47Z"),
            "an offset converts to UTC")
        t.expect(
            PersonalAIUsageTimestamp.parse("2026-10-01T09:22:47+0530")
                == PersonalAIUsageTimestamp.parse("2026-10-01T03:52:47Z"),
            "an offset without a colon converts too")
        t.expect(
            PersonalAIUsageTimestamp.parse("2026-09-30T22:52:47-05:00")
                == PersonalAIUsageTimestamp.parse("2026-10-01T03:52:47Z"),
            "a negative offset converts across a day")

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for sample in ["2026-03-08T10:00:00.250Z", "2031-12-31T23:59:59.999Z", "2026-02-28T00:00:00.000Z"] {
            let expected = formatter.date(from: sample)?.timeIntervalSince1970 ?? .nan
            let actual = PersonalAIUsageTimestamp.parse(sample) ?? .infinity
            t.expect(abs(expected - actual) < 0.001, "\(sample) agrees with ISO8601DateFormatter")
        }

        for bad in [
            "", "garbage", "2026-10-01", "2026-10-01T03:52:47", "2026-13-01T00:00:00Z",
            "2026-02-30T00:00:00Z", "2026-00-10T00:00:00Z", "2026-10-01T24:00:00Z",
            "2026-10-01T03:60:00Z", "2026-10-01T03:52:47.Z", "2026-10-01T03:52:47Zjunk",
            "2026-10-01 03:52:47Z", "1969-12-31T23:59:59Z", "2026-10-01T03:52:47+5:30",
            "2026-10-01T03:52:47+0560", "20261001T035247Z",
        ] {
            t.expect(PersonalAIUsageTimestamp.parse(bad) == nil, "\"\(bad)\" is not a timestamp")
        }
    }

    // MARK: - Claude Code lines

    private static func claudeLines() {
        let entry = PersonalAIUsageLogParser.claudeEntry(claude())
        t.expect(entry?.tokens.input == 2, "claude input tokens come from message.usage")
        t.expect(entry?.tokens.output == 508, "claude output tokens come from message.usage")
        t.expect(entry?.tokens.cache == 32_479, "cache read and creation are summed aside")
        t.expect(entry?.tokens.total == 510, "the headline total leaves cache out")
        t.expect(entry?.key == "msg_1|req_1", "an entry is keyed by message id and request id")
        t.expect(
            abs((entry?.time ?? 0) - 1_790_826_767.057) < 0.0005, "the entry carries its timestamp")

        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(type: "user")) == nil,
            "a user line is not usage")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(type: nil))?.tokens.output == 508,
            "a line with no type but an assistant role still counts")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(type: nil, role: nil)) == nil,
            "a line that names no assistant is skipped")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(usage: nil)) == nil,
            "an assistant line without usage is skipped")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(usage: "null")) == nil,
            "null usage is skipped")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(usage: "{}")) == nil,
            "empty usage is skipped")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(usage: claudeUsage(0, 0))) == nil,
            "a turn that used nothing is not an entry")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(time: nil)) == nil,
            "a line with no timestamp cannot be bucketed")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(claude(time: "yesterday")) == nil,
            "a garbage timestamp is skipped")

        let negative = PersonalAIUsageLogParser.claudeEntry(claude(usage: claudeUsage(-5, 10)))
        t.expect(negative?.tokens.input == 0 && negative?.tokens.output == 10, "a negative count is 0")
        let text = PersonalAIUsageLogParser.claudeEntry(
            claude(usage: #"{"input_tokens":"lots","output_tokens":7}"#))
        t.expect(text?.tokens.input == 0 && text?.tokens.output == 7, "a text count is 0")
        let whole = PersonalAIUsageLogParser.claudeEntry(
            claude(usage: #"{"input_tokens":12.0,"output_tokens":3}"#))
        t.expect(whole?.tokens.input == 12, "a whole-number float is a count")
        let fraction = PersonalAIUsageLogParser.claudeEntry(
            claude(usage: #"{"input_tokens":12.5,"output_tokens":3}"#))
        t.expect(fraction?.tokens.input == 0 && fraction?.tokens.output == 3, "a fractional count is 0")
        let huge = PersonalAIUsageLogParser.claudeEntry(
            claude(usage: #"{"input_tokens":9000000000000000000,"output_tokens":1e30}"#))
        t.expect(
            huge?.tokens.input == PersonalAIUsageLogParser.maxCount && huge?.tokens.output == 0,
            "an absurd count is capped and an unrepresentable one is dropped")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(
                claude(usage: #"{"input_tokens":"a","output_tokens":null}"#)) == nil,
            "usage with no readable count is skipped")
        t.expect(
            PersonalAIUsageLogParser.claudeEntry(
                claude(usage: #"{"input_tokens":-1,"output_tokens":-2}"#)) == nil,
            "usage of only negative counts is skipped")

        for garbage in [
            "", "   ", "not json", "[1,2,3]", "42", "null", #"{"type":"assistant""#,
            #"{"type":"assistant","message":5,"usage":1}"#,
            #"{"type":7,"timestamp":null,"message":{"usage":{"input_tokens":1}}}"#,
            #"{"type":"assistant","timestamp":"2026-10-01T03:52:47Z","message":"usage"}"#,
            "\u{0}\u{1}binary\u{2}", String(repeating: "{", count: 500),
        ] {
            t.expect(
                PersonalAIUsageLogParser.claudeEntry(line(garbage)) == nil,
                "garbage line is skipped: \(garbage.prefix(24))")
        }

        var log = PersonalAIUsageClaudeLog()
        log.consume(claude(id: "a", usage: claudeUsage(10, 20)))
        log.consume(line("not json"))
        log.consume(Data(claude(id: "b", usage: claudeUsage(1, 2)) + Data("\r".utf8)))
        t.expect(log.entries.count == 2, "a bad line costs nothing else, and CRLF still parses")
    }

    private static func claudeDeduplication() {
        var streamed = PersonalAIUsageClaudeLog()
        streamed.consume(claude(usage: #"{"input_tokens":2,"output_tokens":1}"#))
        streamed.consume(claude(time: "2026-10-01T03:52:49.000Z", usage: claudeUsage(2, 508)))
        streamed.consume(claude(time: "2026-10-01T03:52:50.000Z", usage: claudeUsage(2, 508)))
        t.expect(streamed.entries.count == 1, "one streamed message is one entry")
        t.expect(
            streamed.entries.first?.tokens.output == 508, "the grown count wins, not the sum")
        t.expect(
            abs((streamed.entries.first?.time ?? 0) - 1_790_826_767.057) < 0.0005,
            "the earliest line decides the day")

        var distinct = PersonalAIUsageClaudeLog()
        distinct.consume(claude(id: "m", request: "r1", usage: claudeUsage(5, 5)))
        distinct.consume(claude(id: "m", request: "r2", usage: claudeUsage(5, 5)))
        distinct.consume(claude(id: "n", request: "r1", usage: claudeUsage(5, 5)))
        t.expect(distinct.entries.count == 3, "a different request or message is a different turn")

        var anonymous = PersonalAIUsageClaudeLog()
        anonymous.consume(claude(id: nil, request: nil, usage: claudeUsage(5, 5)))
        anonymous.consume(claude(id: nil, request: nil, usage: claudeUsage(5, 5)))
        t.expect(anonymous.entries.count == 2, "a line with no message id cannot be merged")

        var withoutRequest = PersonalAIUsageClaudeLog()
        withoutRequest.consume(claude(id: "m", request: nil, usage: claudeUsage(5, 5)))
        withoutRequest.consume(claude(id: "m", request: nil, usage: claudeUsage(5, 5)))
        t.expect(withoutRequest.entries.count == 1, "a missing request id still merges on the message id")

        var files = PersonalAIUsageDeduper()
        files.add(contentsOf: PersonalAIUsageClaudeLog.entries(of: [claude(id: "x", usage: claudeUsage(3, 4))]))
        files.add(contentsOf: PersonalAIUsageClaudeLog.entries(of: [claude(id: "x", usage: claudeUsage(3, 4))]))
        t.expect(
            files.entries.count == 1 && files.entries[0].tokens.total == 7,
            "a turn copied into a resumed session's file counts once")
    }

    // MARK: - Codex lines

    private static func codexTotals() {
        var log = PersonalAIUsageCodexLog()
        log.consume(codex("2026-10-01T03:52:56.945Z", input: 100, cached: 40, output: 10))
        log.consume(codex("2026-10-01T03:52:57.000Z", input: 100, cached: 40, output: 10))
        log.consume(codex("2026-10-01T03:53:40.608Z", input: 250, cached: 100, output: 30))
        t.expect(log.entries.count == 2, "a repeated event adds nothing")
        t.expect(
            log.entries.first?.tokens == PersonalAIUsageTokens(input: 60, output: 10, cache: 40),
            "the first event counts the session so far, cached input aside")
        t.expect(
            log.entries.last?.tokens == PersonalAIUsageTokens(input: 90, output: 20, cache: 60),
            "later events count only their growth")
        let sum = log.entries.reduce(PersonalAIUsageTokens.zero) { $0 + $1.tokens }
        t.expect(
            sum == PersonalAIUsageTokens(input: 150, output: 30, cache: 100),
            "growth sums back to the final totals: nothing counted twice")
        t.expect(
            abs((log.entries.last?.time ?? 0) - 1_790_826_820.608) < 0.0005,
            "growth belongs to the moment it was reported")
        t.expect(log.entries.allSatisfy { $0.key == nil }, "codex entries are never merged by key")

        var midnight = PersonalAIUsageCodexLog()
        midnight.consume(codex("2026-10-01T23:59:00Z", input: 1_000, output: 100))
        midnight.consume(codex("2026-10-02T00:01:00Z", input: 1_500, output: 160))
        t.expect(
            midnight.entries.map(\.tokens.total) == [1_100, 560],
            "a session across midnight splits by when each event happened")

        var restarted = PersonalAIUsageCodexLog()
        restarted.consume(codex("2026-10-01T03:00:00Z", input: 500, output: 50))
        restarted.consume(codex("2026-10-01T04:00:00Z", input: 80, output: 5))
        restarted.consume(codex("2026-10-01T05:00:00Z", input: 100, output: 9))
        t.expect(
            restarted.entries.map(\.tokens.total) == [550, 85, 24],
            "a counter that fell restarted, so what follows is new")

        var noisy = PersonalAIUsageCodexLog()
        noisy.consume(
            line(
                #"{"timestamp":"2026-10-01T03:00:00Z","type":"event_msg","#
                    + #""payload":{"type":"token_count","info":null}}"#))
        noisy.consume(codex("2026-10-01T03:00:01Z", input: 10, output: 1, type: "agent_message"))
        noisy.consume(line(#"{"timestamp":"2026-10-01T03:00:02Z","type":"turn_context","payload":{"type":"token_count"}}"#))
        noisy.consume(line("token_count but not json"))
        noisy.consume(
            line(
                #"{"timestamp":"2026-10-01T03:00:03Z","payload":{"type":"token_count","#
                    + #""info":{"total_token_usage":{"input_tokens":"x","output_tokens":null}}}}"#))
        noisy.consume(
            line(
                #"{"timestamp":"never","payload":{"type":"token_count","info":{"#
                    + #""total_token_usage":{"input_tokens":5,"output_tokens":1}}}}"#))
        t.expect(noisy.entries.isEmpty, "events without readable totals or time are skipped")
        noisy.consume(codex("2026-10-01T03:01:00Z", input: 20, output: 2))
        t.expect(noisy.entries.count == 1, "skipped lines do not disturb the baseline")

        var cachedHeavy = PersonalAIUsageCodexLog()
        cachedHeavy.consume(codex("2026-10-01T03:00:00Z", input: 10, cached: 50, output: 1))
        t.expect(
            cachedHeavy.entries.first?.tokens == PersonalAIUsageTokens(input: 0, output: 1, cache: 10),
            "cached input can never exceed input")

        let negative = PersonalAIUsageLogParser.codexSample(
            codex("2026-10-01T03:00:00Z", input: -5, cached: -1, output: 9))
        t.expect(
            negative?.totals == PersonalAIUsageCodexSample.Totals(input: 0, cachedInput: 0, output: 9),
            "negative totals read as 0")
    }

    // MARK: - Ranges

    private static func ranges() {
        let cal = utc()
        let now = date("2026-10-05T19:29:04Z")

        let today = PersonalAIUsageRange.today.interval(now: now, calendar: cal)
        t.expect(today.start == date("2026-10-05T00:00:00Z"), "today starts at local midnight")
        t.expect(today.end == date("2026-10-06T00:00:00Z"), "today ends at the next midnight")

        let week = PersonalAIUsageRange.last7Days.interval(now: now, calendar: cal)
        t.expect(week.start == date("2026-09-29T00:00:00Z"), "7 days is today and the six before")
        t.expect(PersonalAIUsageRange.last7Days.dayStarts(now: now, calendar: cal).count == 7, "7 days is 7 buckets")

        let month = PersonalAIUsageRange.last30Days.interval(now: now, calendar: cal)
        t.expect(month.start == date("2026-09-06T00:00:00Z"), "30 days is today and the 29 before")
        t.expect(PersonalAIUsageRange.last30Days.dayStarts(now: now, calendar: cal).count == 30, "30 days is 30 buckets")

        let toDate = PersonalAIUsageRange.monthToDate.interval(now: now, calendar: cal)
        t.expect(toDate.start == date("2026-10-01T00:00:00Z"), "month to date starts on the 1st")
        let toDateDays = PersonalAIUsageRange.monthToDate.dayStarts(now: now, calendar: cal)
        t.expect(toDateDays.count == 5, "the 5th is five days into the month")
        t.expect(toDateDays.last == date("2026-10-05T00:00:00Z"), "the last bucket is today")

        let firstMoment = date("2026-10-01T00:00:30Z")
        t.expect(
            PersonalAIUsageRange.monthToDate.dayStarts(now: firstMoment, calendar: cal).count == 1,
            "the first minute of a month is one day")
        let lastMoment = date("2026-10-31T23:59:59Z")
        t.expect(
            PersonalAIUsageRange.monthToDate.dayStarts(now: lastMoment, calendar: cal).count == 31,
            "the last second of a month is the whole month")

        let early = date("2026-03-03T10:00:00Z")
        t.expect(
            PersonalAIUsageRange.last30Days.interval(now: early, calendar: cal).start
                == date("2026-02-02T00:00:00Z"),
            "30 days reaches back across a short February")
        t.expect(
            PersonalAIUsageRange.monthToDate.dayStarts(now: early, calendar: cal).count == 3,
            "month to date does not reach into the previous month")

        let yearStart = date("2027-01-02T08:00:00Z")
        t.expect(
            PersonalAIUsageRange.last7Days.interval(now: yearStart, calendar: cal).start
                == date("2026-12-27T00:00:00Z"),
            "7 days reaches back across a new year")

        let kolkata = calendar("Asia/Kolkata")
        t.expect(
            PersonalAIUsageRange.today.interval(now: now, calendar: kolkata).start
                == date("2026-10-05T18:30:00Z"),
            "19:29 UTC is already tomorrow in Kolkata, so today began at 18:30 UTC")

        let losAngeles = calendar("America/Los_Angeles")
        let afterFallBack = date("2026-11-03T20:00:00Z")
        let starts = PersonalAIUsageRange.last7Days.dayStarts(now: afterFallBack, calendar: losAngeles)
        t.expect(starts.count == 7, "a week across a DST change is still 7 buckets")
        t.expect(starts.first == date("2026-10-28T07:00:00Z"), "a day before the change starts at 07:00 UTC")
        t.expect(starts.last == date("2026-11-03T08:00:00Z"), "a day after the change starts at 08:00 UTC")
        for range in PersonalAIUsageRange.allCases {
            let last = range.dayStarts(now: now, calendar: cal).last
            t.expect(last == date("2026-10-05T00:00:00Z"), "\(range.title) ends on today")
        }

        let noon = date("2026-10-05T12:00:00Z")
        t.expect(PersonalAIUsageSchedule.delay(now: noon, calendar: cal) == 300, "rescans come every five minutes")
        t.expect(
            PersonalAIUsageSchedule.delay(now: date("2026-10-05T23:58:00Z"), calendar: cal) == 121,
            "a rescan comes just after midnight when that is sooner")
        t.expect(
            PersonalAIUsageSchedule.delay(now: date("2026-10-05T23:59:59.5Z"), calendar: cal) >= 1,
            "the wait is never shorter than a second")
        t.expect(PersonalAIUsageSchedule.isStale(since: nil, now: noon), "never fetched is stale")
        t.expect(
            !PersonalAIUsageSchedule.isStale(since: noon.addingTimeInterval(-299), now: noon),
            "299 seconds old is fresh")
        t.expect(
            PersonalAIUsageSchedule.isStale(since: noon.addingTimeInterval(-300), now: noon),
            "five minutes old is stale")
    }

    // MARK: - Bucketing

    private static func entry(_ iso: String, input: Int, output: Int = 0) -> PersonalAIUsageEntry {
        PersonalAIUsageEntry(
            key: nil, time: PersonalAIUsageTimestamp.parse(iso) ?? .nan,
            tokens: PersonalAIUsageTokens(input: input, output: output))
    }

    private static func bucketing() {
        let kolkata = calendar("Asia/Kolkata")
        let now = date("2026-10-06T06:30:00Z")
        let entries = [
            entry("2026-10-05T18:29:59Z", input: 100),
            entry("2026-10-05T18:30:00Z", input: 7, output: 3),
            entry("2026-10-04T18:30:00Z", input: 1),
            entry("2026-10-04T18:29:59Z", input: 50),
            entry("2026-10-06T18:29:59Z", input: 1_000),
            entry("2026-10-06T18:30:00Z", input: 9_999),
            entry("2025-01-01T00:00:00Z", input: 8_888),
        ]
        let week = PersonalAIUsageAggregator.series(
            entries: entries, range: .last7Days, now: now, calendar: kolkata)
        t.expect(week.days.count == 7, "a series has a bucket for every day")
        t.expect(week.days.last?.tokens.input == 1_007, "IST 00:00 and the rest of the day land on today")
        t.expect(week.days[5].tokens.input == 101, "UTC 18:29:59 is still the previous local day")
        t.expect(week.days[4].tokens.input == 50, "a minute earlier is the day before that")
        t.expect(week.days[3].tokens.input == 0, "a day with no entries is an empty bucket")
        t.expect(week.total.input == 1_158, "entries after tonight and before the window are dropped")
        t.expect(week.today.output == 3, "today is the last bucket")

        let today = PersonalAIUsageAggregator.series(
            entries: entries, range: .today, now: now, calendar: kolkata)
        t.expect(today.days.count == 1 && today.total.total == 1_010, "the Today range holds only today")

        let utcDays = PersonalAIUsageAggregator.series(
            entries: entries, range: .today, now: now, calendar: utc())
        t.expect(utcDays.total.input == 10_999, "the same entries bucket differently in UTC")

        let shape = PersonalAIUsageSeries(days: [
            PersonalAIUsageDay(start: date("2026-10-03T00:00:00Z"), tokens: PersonalAIUsageTokens(input: 100)),
            PersonalAIUsageDay(start: date("2026-10-04T00:00:00Z"), tokens: PersonalAIUsageTokens(input: 20, output: 30)),
        ])
        t.expect(shape.todayShare == 0.5, "today against the busiest day")
        t.expect(shape.busiestDayTotal == 100, "the busiest day is the largest total")
        let peak = PersonalAIUsageSeries(days: [
            PersonalAIUsageDay(start: date("2026-10-03T00:00:00Z"), tokens: PersonalAIUsageTokens(input: 5)),
            PersonalAIUsageDay(start: date("2026-10-04T00:00:00Z"), tokens: PersonalAIUsageTokens(input: 50)),
        ])
        t.expect(peak.todayShare == 1, "a record day fills the ring")
        let quiet = PersonalAIUsageSeries(days: [
            PersonalAIUsageDay(start: date("2026-10-04T00:00:00Z"), tokens: .zero),
        ])
        t.expect(quiet.todayShare == 0 && !quiet.hasActivity, "no tokens is no activity and an empty ring")
        t.expect(!PersonalAIUsageSeries(days: []).hasActivity, "an empty series has no activity")
    }

    // MARK: - Limits

    private static func limitWindows() {
        let window = PersonalAIUsageLimitWindow(usedPercent: 28, durationMinutes: 300, resetsAt: nil)
        t.expect(window.remaining == 72 && window.used == 28, "remaining is the rest of 100")
        t.expect(window.percent(.remaining) == 72 && window.percent(.used) == 28, "the measure picks the figure")
        t.expect(window.fraction(.remaining) == 0.72, "a fraction is the percent over 100")
        t.expect(window.caption(.remaining) == "72% left", "remaining reads as left")
        t.expect(window.caption(.used) == "28% used", "used reads as used")

        let over = PersonalAIUsageLimitWindow(usedPercent: 130, durationMinutes: nil, resetsAt: nil)
        t.expect(over.used == 100 && over.remaining == 0, "above 100 is clamped to a spent window")
        let under = PersonalAIUsageLimitWindow(usedPercent: -20, durationMinutes: nil, resetsAt: nil)
        t.expect(under.used == 0 && under.remaining == 100, "below 0 is clamped to a fresh window")
        t.expect(under.fraction(.used) == 0 && over.fraction(.remaining) == 0, "fractions stay in range")

        let labels: [(Int, String, String)] = [
            (300, "5-hour", "5h"), (10_080, "Weekly", "Week"), (1_440, "Daily", "1d"),
            (60, "1-hour", "1h"), (45, "45-minute", "45m"), (4_320, "3-day", "3d"),
            (90, "90-minute", "90m"), (480, "8-hour", "8h"), (43_200, "30-day", "30d"),
            (0, "Limit", "Limit"), (-5, "Limit", "Limit"), (1, "1-minute", "1m"),
        ]
        for (minutes, title, short) in labels {
            t.expect(PersonalAIUsageLimitLabel.title(minutes: minutes) == title, "\(minutes) minutes is \(title)")
            t.expect(PersonalAIUsageLimitLabel.shortTitle(minutes: minutes) == short, "\(minutes) minutes is \(short) short")
        }
        t.expect(window.title(fallback: "Primary") == "5-hour", "a window is named by its length")
        t.expect(over.title(fallback: "Primary") == "Primary", "a window with no length takes the fallback")
        t.expect(over.shortTitle(fallback: "Main") == "Main", "the short name falls back too")
    }

    private static func resetPhrases() {
        let cal = utc()
        let now = date("2026-10-05T12:00:00Z")
        func phrase(_ seconds: TimeInterval) -> String {
            PersonalAIUsageReset.phrase(now.addingTimeInterval(seconds), now: now, calendar: cal)
        }
        t.expect(phrase(2 * 3_600 + 10 * 60 + 30) == "in 2h 10m", "a countdown in hours and minutes")
        t.expect(phrase(2 * 3_600) == "in 2h", "whole hours drop the minutes")
        t.expect(phrase(45 * 60) == "in 45m", "under an hour is minutes")
        t.expect(phrase(30) == "in under a minute", "under a minute is said so")
        t.expect(phrase(0) == "now" && phrase(-300) == "now", "a reset in the past is now")
        t.expect(phrase(24 * 3_600 - 60) == "in 23h 59m", "just under a day still counts down")
        t.expect(phrase(24 * 3_600) == "Tue", "a day out names the weekday")
        t.expect(phrase(3 * 86_400) == "Thu", "three days out names the weekday")
        t.expect(phrase(7 * 86_400 - 1) == "Mon", "just under a week is the weekday")
        t.expect(phrase(7 * 86_400) == "Oct 12", "a week out gives the date")
        let kolkata = calendar("Asia/Kolkata")
        t.expect(
            PersonalAIUsageReset.phrase(date("2026-10-06T19:00:00Z"), now: now, calendar: kolkata)
                == "Wed",
            "the weekday is the viewer's: 19:00 UTC Tuesday is Wednesday in Kolkata")
    }

    // MARK: - Formatting and settings

    private static func formatting() {
        let cases: [(Int, String)] = [
            (0, "0"), (7, "7"), (842, "842"), (999, "999"), (1_000, "1K"), (1_050, "1.1K"),
            (1_234, "1.2K"), (9_949, "9.9K"), (9_950, "10K"), (12_345, "12K"),
            (123_456, "123K"), (999_499, "999K"), (999_500, "1M"), (1_000_000, "1M"),
            (1_234_567, "1.2M"), (12_345_678, "12M"), (999_999_999, "1B"), (1_500_000_000, "1.5B"),
            (2_000_000_000_000, "2T"), (-4, "0"),
        ]
        for (count, text) in cases {
            let read = PersonalAIUsageFormat.tokens(count)
            t.expect(read == text, "\(count) tokens read \(text), not \(read)")
        }
        t.expect(
            PersonalAIUsageFormat.tokens(Int.max) == "100000T", "an absurd count neither traps nor wraps")
        t.expect(
            PersonalAIUsageFormat.exact(1_234_567, locale: Locale(identifier: "en_US")) == "1,234,567",
            "an exact count is grouped")
    }

    private static func settingsAndContent() {
        let standard = PersonalAIUsageSettings(
            content: nil, range: nil, display: nil, measure: nil, limitsSource: nil)
        t.expect(
            standard == PersonalAIUsageSettings() && standard.content == .limits
                && standard.range == .last7Days && standard.display == .rings
                && standard.measure == .remaining && standard.limitsSource == .codex,
            "unset preferences are the documented defaults")
        let garbage = PersonalAIUsageSettings(
            content: "", range: "yesterday", display: "3d", measure: "x", limitsSource: "gemini")
        t.expect(garbage == standard, "unrecognised preferences fall back to the defaults")
        let chosen = PersonalAIUsageSettings(
            content: "activity", range: "monthToDate", display: "bars", measure: "used",
            limitsSource: "claude")
        t.expect(
            chosen.content == .activity && chosen.range == .monthToDate && chosen.display == .bars
                && chosen.measure == .used && chosen.limitsSource == .claude,
            "every preference value reads back")

        let both = PersonalAIUsageContent.resolve(preferred: .limits, hasLimits: true, hasActivity: true)
        t.expect(both == PersonalAIUsageResolution(content: .limits, isFallback: false), "the chosen kind shows when it has data")
        let activityFirst = PersonalAIUsageContent.resolve(preferred: .activity, hasLimits: true, hasActivity: true)
        t.expect(activityFirst?.content == .activity && activityFirst?.isFallback == false, "activity can be the chosen kind")
        let fallback = PersonalAIUsageContent.resolve(preferred: .limits, hasLimits: false, hasActivity: true)
        t.expect(fallback == PersonalAIUsageResolution(content: .activity, isFallback: true), "an empty kind falls back, visibly")
        let reverse = PersonalAIUsageContent.resolve(preferred: .activity, hasLimits: true, hasActivity: false)
        t.expect(reverse == PersonalAIUsageResolution(content: .limits, isFallback: true), "the fallback works both ways")
        t.expect(
            PersonalAIUsageContent.resolve(preferred: .limits, hasLimits: false, hasActivity: false) == nil,
            "no data anywhere resolves to nothing")
    }

    // MARK: - Scanner

    private static func scanner() {
        let fm = FileManager.default
        let home = fm.temporaryDirectory.appending(path: "ai-usage-checks-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? fm.removeItem(at: home) }
        let claudeRoot = PersonalAIUsageScanner.folder(for: .claudeCode, home: home)
        let codexRoot = PersonalAIUsageScanner.folder(for: .codex, home: home)
        t.expect(claudeRoot.path.hasSuffix("/.claude/projects"), "claude logs live under ~/.claude/projects")
        t.expect(codexRoot.path.hasSuffix("/.codex/sessions"), "codex logs live under ~/.codex/sessions")

        let missing = PersonalAIUsageScanner.scan(home: home, modifiedSince: .distantPast, cache: PersonalAIUsageFileCache())
        t.expect(
            missing.foundFolders.isEmpty && missing.isComplete && missing.openedFiles == 0
                && missing.entries.values.allSatisfy(\.isEmpty),
            "a Mac with neither tool scans cleanly to nothing")

        let now = Date()
        func write(_ lines: [Data], to url: URL, modified: Date, newline: Bool = true) {
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            var data = Data()
            for (index, text) in lines.enumerated() {
                data.append(text)
                if newline || index < lines.count - 1 { data.append(0x0A) }
            }
            try? data.write(to: url)
            try? fm.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        }
        func iso(_ date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter.string(from: date)
        }
        let recent = iso(now.addingTimeInterval(-3_600))
        let older = iso(now.addingTimeInterval(-10 * 86_400))

        let fresh = claudeRoot.appending(path: "-Users-me-app/fresh.jsonl")
        write(
            [
                claude(id: "m1", request: "r1", time: recent, usage: claudeUsage(10, 20)),
                claude(id: "m1", request: "r1", time: recent, usage: claudeUsage(10, 20)),
                line("garbage line"),
                claude(id: "m2", request: "r2", time: recent, type: "user"),
                claude(id: "m3", request: "r3", time: recent, usage: claudeUsage(1, 2)),
            ], to: fresh, modified: now)
        let resumed = claudeRoot.appending(path: "-Users-me-app/resumed.jsonl")
        write(
            [claude(id: "m3", request: "r3", time: recent, usage: claudeUsage(1, 2)),
             claude(id: "m4", request: "r4", time: recent, usage: claudeUsage(100, 200))],
            to: resumed, modified: now)
        let stale = claudeRoot.appending(path: "-Users-me-old/stale.jsonl")
        write(
            [claude(id: "m9", request: "r9", time: older, usage: claudeUsage(1_000, 2_000))],
            to: stale, modified: now.addingTimeInterval(-10 * 86_400))
        write([line("{}")], to: claudeRoot.appending(path: "-Users-me-app/notes.txt"), modified: now)
        write(
            [claude(id: "h", request: "h", time: recent, usage: claudeUsage(5_000, 5_000))],
            to: claudeRoot.appending(path: ".hidden/secret.jsonl"), modified: now)
        let session = codexRoot.appending(path: "2026/10/01/rollout-a.jsonl")
        write(
            [
                line(#"{"type":"session_meta","payload":{"id":"x"}}"#),
                codex(recent, input: 300, cached: 100, output: 30),
                codex(recent, input: 300, cached: 100, output: 30),
                codex(recent, input: 500, cached: 250, output: 80),
            ], to: session, modified: now)

        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        var scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: PersonalAIUsageFileCache())
        let claudeEntries = scan.entries[.claudeCode] ?? []
        let claudeSum = claudeEntries.reduce(PersonalAIUsageTokens.zero) { $0 + $1.tokens }
        t.expect(scan.foundFolders == [.claudeCode, .codex], "both log folders are found")
        t.expect(scan.isComplete && scan.unreadableFiles == 0, "a clean scan is complete")
        t.expect(claudeEntries.count == 3, "claude: duplicate lines and a copied turn count once; others skipped")
        t.expect(claudeSum.input == 111 && claudeSum.output == 222, "claude totals are the unique turns' sum")
        t.expect(scan.openedFiles == 3, "only the two claude files in range and the codex file are opened")
        t.expect(
            !claudeEntries.contains { $0.tokens.input == 1_000 },
            "a file last written before the range is never opened")
        t.expect(
            !claudeEntries.contains { $0.tokens.input == 5_000 }, "a hidden folder is not scanned")
        let codexSum = (scan.entries[.codex] ?? []).reduce(PersonalAIUsageTokens.zero) { $0 + $1.tokens }
        t.expect(
            codexSum == PersonalAIUsageTokens(input: 250, output: 80, cache: 250),
            "codex: cumulative totals become growth, repeats ignored, cached input aside")

        let again = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: scan.cache)
        t.expect(again.openedFiles == 0, "an unchanged tree is served entirely from the cache")
        t.expect(
            (again.entries[.claudeCode] ?? []).count == 3 && (again.entries[.codex] ?? []).count == 2,
            "cached results equal fresh ones")

        let wider = PersonalAIUsageScanner.scan(
            home: home, modifiedSince: now.addingTimeInterval(-30 * 86_400), cache: again.cache)
        t.expect(wider.openedFiles == 1, "widening the range opens only the newly eligible file")
        t.expect(
            (wider.entries[.claudeCode] ?? []).contains { $0.tokens.input == 1_000 },
            "the older file now counts")
        let narrow = PersonalAIUsageScanner.scan(
            home: home, modifiedSince: now.addingTimeInterval(60), cache: wider.cache)
        t.expect(
            narrow.openedFiles == 0 && narrow.entries.values.allSatisfy(\.isEmpty),
            "a window after every write opens nothing and finds nothing")

        write(
            [claude(id: "m1", request: "r1", time: recent, usage: claudeUsage(10, 20)),
             claude(id: "m5", request: "r5", time: recent, usage: claudeUsage(7, 7))],
            to: fresh, modified: now.addingTimeInterval(5))
        scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: again.cache)
        t.expect(scan.openedFiles == 1, "a rewritten file is reread and nothing else")
        t.expect(
            (scan.entries[.claudeCode] ?? []).map(\.tokens.input).sorted() == [1, 7, 10, 100],
            "the rewrite replaces the file's old entries; the resumed copy's turns remain")

        try? fm.removeItem(at: resumed)
        scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: scan.cache)
        t.expect(
            !scan.cache.files.keys.contains { $0.hasSuffix("resumed.jsonl") },
            "a deleted log leaves the cache")
        t.expect(
            (scan.entries[.claudeCode] ?? []).count == 2,
            "a deleted log's turns no longer count")

        let locked = claudeRoot.appending(path: "-Users-me-app/locked.jsonl")
        write([claude(id: "l", request: "l", time: recent, usage: claudeUsage(9, 9))], to: locked, modified: now)
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: scan.cache)
        if !fm.isReadableFile(atPath: locked.path) {
            t.expect(scan.unreadableFiles == 1, "an unreadable file is counted, not fatal")
            t.expect(scan.isComplete, "an unreadable file does not abort the scan")
            t.expect(
                (scan.entries[.claudeCode] ?? []).count == 2 && !(scan.entries[.codex] ?? []).isEmpty,
                "everything else is still read")
        }
        try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: scan.cache)
        t.expect((scan.entries[.claudeCode] ?? []).count == 3, "a file that becomes readable is picked up")

        let tail = claudeRoot.appending(path: "-Users-me-tail/tail.jsonl")
        write(
            [claude(id: "t1", request: "t1", time: recent, usage: claudeUsage(2, 2)),
             claude(id: "t2", request: "t2", time: recent, usage: claudeUsage(3, 3)),
             line(#"{"type":"assistant","timestamp":"\#(recent)","message":{"id":"t3","usage":{"input_tokens":4"#)],
            to: tail, modified: now, newline: false)
        scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: scan.cache)
        t.expect(
            (scan.entries[.claudeCode] ?? []).filter { $0.key?.hasPrefix("t") == true }.count == 2,
            "a half-written last line is skipped and the lines before it count")
        write(
            [claude(id: "t1", request: "t1", time: recent, usage: claudeUsage(2, 2)),
             claude(id: "t2", request: "t2", time: recent, usage: claudeUsage(3, 3)),
             claude(id: "t3", request: "t3", time: recent, usage: claudeUsage(4, 4))],
            to: tail, modified: now.addingTimeInterval(9), newline: false)
        scan = PersonalAIUsageScanner.scan(home: home, modifiedSince: weekAgo, cache: scan.cache)
        t.expect(
            (scan.entries[.claudeCode] ?? []).filter { $0.key?.hasPrefix("t") == true }.count == 3,
            "a complete last line without a trailing newline counts")

        largeFile(home: home, now: now, recent: recent)
    }

    /// Lines straddle every 1 MiB read, and a multi-megabyte blob sits among them.
    private static func largeFile(home: URL, now: Date, recent: String) {
        let fm = FileManager.default
        let url = PersonalAIUsageScanner.folder(for: .claudeCode, home: home)
            .appending(path: "-Users-me-big/big.jsonl")
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        let count = 20_000
        for index in 0..<count {
            data.append(claude(id: "big\(index)", request: "r\(index)", time: recent, usage: claudeUsage(1, 2)))
            data.append(0x0A)
            if index == 9_000 {
                data.append(Data(repeating: UInt8(ascii: "x"), count: 3 << 20))
                data.append(0x0A)
            }
            if index % 5_000 == 0 {
                data.append(Data("not json\n\n".utf8))
            }
        }
        try? data.write(to: url)
        try? fm.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
        let scan = PersonalAIUsageScanner.scan(
            home: home, modifiedSince: now.addingTimeInterval(-86_400), cache: PersonalAIUsageFileCache())
        let big = (scan.entries[.claudeCode] ?? []).filter { $0.key?.hasPrefix("big") == true }
        t.expect(data.count > 4 << 20, "the large fixture spans several read chunks")
        t.expect(big.count == count, "every line is read exactly once across chunk boundaries")
        t.expect(
            big.reduce(0) { $0 + $1.tokens.total } == count * 3,
            "no line is split, lost or duplicated at a chunk boundary")
    }
}

extension PersonalAIUsageClaudeLog {
    fileprivate static func entries(of lines: [Data]) -> [PersonalAIUsageEntry] {
        var log = PersonalAIUsageClaudeLog()
        for line in lines { log.consume(line) }
        return log.entries
    }
}

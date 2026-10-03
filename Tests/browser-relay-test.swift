// The relay's tab list is read as pages only, a tab is reused only on the URL's exact host, and
// the endpoint is the port the user set — or the relay's own default when they set no usable one.
import Foundation

@main
struct BrowserRelayPageTests {
    nonisolated(unsafe) static var failures = 0
    nonisolated(unsafe) static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("✗ \(message)")
        }
    }

    static func main() {
        keepsOnlyPages()
        reusesOnlyTheExactHost()
        clipsOnlyPastTheLimit()
        dialsTheConfiguredPortOrTheDefault()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static let list = Data(
        """
        [{"id":"P1","type":"page","title":"Search | Splunk","url":"https://splunk-us.corp.adobe.com/en-US/app/search","faviconUrl":"x"},
         {"id":"W1","type":"service_worker","title":"sw","url":"https://splunk-us.corp.adobe.com/sw.js"},
         {"id":"P2","type":"page","title":"EU","url":"https://splunk-eu.corp.adobe.com/"}]
        """.utf8)

    static func keepsOnlyPages() {
        let pages = (try? BrowserRelayPage.pages(fromList: list)) ?? []
        expect(pages.map(\.id) == ["P1", "P2"], "workers are dropped, pages kept in order: \(pages)")
        expect((try? BrowserRelayPage.pages(fromList: Data("{}".utf8))) == nil, "a non-list is an error")
    }

    static func reusesOnlyTheExactHost() {
        let pages = (try? BrowserRelayPage.pages(fromList: list)) ?? []
        let us = URL(string: "https://SPLUNK-US.corp.adobe.com/en-US/app/search/search?q=x")!
        expect(BrowserRelayPage.reusable(for: us, in: pages)?.id == "P1", "same host, any case, reuses")
        let sibling = URL(string: "https://splunk-ap.corp.adobe.com/")!
        expect(BrowserRelayPage.reusable(for: sibling, in: pages) == nil, "a sibling host never reuses")
        let parent = URL(string: "https://corp.adobe.com/")!
        expect(BrowserRelayPage.reusable(for: parent, in: pages) == nil, "a parent domain never reuses")
    }

    static func clipsOnlyPastTheLimit() {
        expect(BrowserRelayPage.clipped("abcde", to: 5) == "abcde", "text at the limit is untouched")
        let cut = BrowserRelayPage.clipped("abcdefgh", to: 5)
        expect(cut.hasPrefix("abcde\n") && cut.contains("3 more characters"), "over the limit: \(cut)")
    }

    static func dialsTheConfiguredPortOrTheDefault() {
        expect(
            BrowserRelayClient().endpoint == "127.0.0.1:9224",
            "unset dials the relay's own default: \(BrowserRelayClient().endpoint)")
        expect(
            BrowserRelayClient(port: 9333).endpoint == "127.0.0.1:9333",
            "a configured port is dialled: \(BrowserRelayClient(port: 9333).endpoint)")
        for unusable in [0, -1, 65536, Int.max] {
            expect(
                BrowserRelayClient(port: unusable).endpoint == "127.0.0.1:9224",
                "\(unusable) is no port a listener holds, so the default answers: "
                    + "\(BrowserRelayClient(port: unusable).endpoint)")
        }
        expect(
            BrowserRelayClient.isValidPort(1) && BrowserRelayClient.isValidPort(65535),
            "1 and 65535 are the ends of the range")
        expect(
            !BrowserRelayClient.isValidPort(0) && !BrowserRelayClient.isValidPort(65536),
            "and neither end past them is")
        let named = BrowserRelayError.unreachable("127.0.0.1:9333").errorDescription ?? ""
        expect(named.contains("9333"), "the failure names the port it dialled: \(named)")
        expect(!named.contains("9224"), "and not one it did not: \(named)")
    }
}

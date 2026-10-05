import Foundation

/// GitHub Copilot's quotas for the account `gh` is signed in to on github.com.
enum PersonalCopilotUsageClient {
    enum Failure: Error, Equatable {
        case ghMissing
        case signedOut
        case noCopilot
        case server(Int)
        case network(String)
        case unreadable
    }

    private static let endpoint = URL(string: "https://api.github.com/copilot_internal/user")!
    private static let timeout: TimeInterval = 12

    /// Cacheless and cookieless: the response carries the account's quotas and stays in memory.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    /// The token is asked of `gh` each time and never kept, so a re-login or logout applies at once.
    static func fetch() async -> Result<PersonalCopilotQuota, Failure> {
        guard let gh = await ExecutableLocator.locate("gh") else { return .failure(.ghMissing) }
        guard
            let result = try? await ToolRunner.run(
                gh, ["auth", "token", "--hostname", "github.com"], timeout: 10),
            result.succeeded
        else { return .failure(.signedOut) }
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.contains(where: \.isWhitespace) else {
            return .failure(.signedOut)
        }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Onecast", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: return .failure(.signedOut)
        case 403, 404: return .failure(.noCopilot)
        case let status: return .failure(.server(status))
        }
        guard let quota = PersonalCopilotQuota.parse(data) else { return .failure(.unreadable) }
        return .success(quota)
    }
}

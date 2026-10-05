import Foundation
import Security

/// Claude's plan limits for the account Claude Code is signed in to, read with its own sign-in.
enum PersonalClaudeUsageClient {
    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"
    private static let timeout: TimeInterval = 12

    /// Cacheless and cookieless: the response carries the account's limits and stays in memory.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        return URLSession(configuration: config)
    }()

    /// Never refreshes the sign-in itself: that would rotate Claude Code's refresh token under it.
    static func fetch() async -> Result<PersonalAIUsageLimitsReport, PersonalAIUsageLimitsProblem> {
        let credentials: PersonalClaudeCredentials
        switch await Task.detached(priority: .utility, operation: readCredentials).value {
        case .success(let read): credentials = read
        case .failure(let problem): return .failure(problem)
        }
        let expired = PersonalAIUsageLimitsProblem(
            message: "Claude Code's sign-in has lapsed. It renews the next time you use Claude Code.",
            canRetry: true)
        guard !credentials.isExpired(now: Date()) else { return .failure(expired) }

        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // Anthropic rate-limits this endpoint hard for any client that is not Claude Code.
        request.setValue("claude-code/\(await claudeVersion())", forHTTPHeaderField: "User-Agent")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(
                PersonalAIUsageLimitsProblem(message: error.localizedDescription, canRetry: true))
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 401: return .failure(expired)
        case 403:
            return .failure(
                PersonalAIUsageLimitsProblem(
                    message: "This Claude account has no plan limits to show.", canRetry: false))
        case 429:
            return .failure(
                PersonalAIUsageLimitsProblem(
                    message: "Anthropic asked Onecast to slow down; it checks again shortly.",
                    canRetry: true))
        case let status:
            return .failure(
                PersonalAIUsageLimitsProblem(
                    message: "Anthropic answered with an error (\(status)).", canRetry: true))
        }
        guard let report = PersonalClaudeUsage.report(data, plan: credentials.subscription) else {
            return .failure(
                PersonalAIUsageLimitsProblem(
                    message: "Anthropic's answer could not be read.", canRetry: true))
        }
        return .success(report)
    }

    /// Blocking: the keychain may stop to ask the user whether Onecast may read Claude Code's item.
    nonisolated private static func readCredentials()
        -> Result<PersonalClaudeCredentials, PersonalAIUsageLimitsProblem>
    {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let credentials = PersonalClaudeCredentials.parse(data)
            else {
                return .failure(
                    PersonalAIUsageLimitsProblem(
                        message: "Claude Code's sign-in could not be read.", canRetry: false))
            }
            return .success(credentials)
        case errSecItemNotFound:
            return .failure(
                PersonalAIUsageLimitsProblem(
                    message: "Sign in to Claude Code (claude, then /login) to see its limits.",
                    canRetry: true))
        default:
            return .failure(
                PersonalAIUsageLimitsProblem(
                    message: "Onecast was not allowed to read Claude Code's sign-in from the keychain.",
                    canRetry: true))
        }
    }

    /// The installed Claude Code's own version, so the request reads as that client's.
    private static func claudeVersion() async -> String {
        guard let claude = await ExecutableLocator.locate("claude"),
            let result = try? await ToolRunner.run(claude, ["--version"], timeout: 10),
            result.succeeded,
            let version = result.output.split(separator: " ").first
        else { return "2.0.0" }
        return String(version)
    }
}

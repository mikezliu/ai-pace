import Foundation

struct ClaudeProbe: Sendable {
    private let credentialLoader: ClaudeCredentialLoader
    private let accountInfoResolver: ClaudeAccountInfoResolver
    private let apiClient: ClaudeAPIClient

    init(
        credentialLoader: ClaudeCredentialLoader = ClaudeCredentialLoader(),
        accountInfoResolver: ClaudeAccountInfoResolver = ClaudeAccountInfoResolver(),
        apiClient: ClaudeAPIClient = ClaudeAPIClient()
    ) {
        self.credentialLoader = credentialLoader
        self.accountInfoResolver = accountInfoResolver
        self.apiClient = apiClient
    }

    func fetch() async -> ProviderSnapshot {
        do {
            let accountInfo = accountInfoResolver.resolve()
            let resolution = credentialLoader.resolveCredentials()

            guard var credentials = resolution.credentials else {
                if let issue = resolution.issue {
                    throw ProcessRunnerError.invalidResponse(issue.message)
                }
                if let statusData = try? await apiClient.fetchStatus(), statusData.loggedIn == true {
                    throw ProcessRunnerError.invalidResponse("Claude is logged in, but credentials could not be read from file, AIPace setup-token, environment, or Keychain.")
                }
                throw ProcessRunnerError.invalidResponse("Claude credentials not found.")
            }

            if credentialLoader.needsRefresh(credentials.oauth) {
                if !credentials.source.supportsRefresh {
                    // setup-token style credentials have no refresh flow; use them as-is
                } else if credentials.oauth.refreshToken != nil {
                    credentials = try await apiClient.refreshToken(credentials, credentialLoader)
                } else {
                    throw ProcessRunnerError.invalidResponse("Claude session expired; log in again.")
                }
            }

            let usage: ClaudeUsageResponse
            do {
                usage = try await apiClient.fetchUsage(credentials.oauth.accessToken)
            } catch let error as ProcessRunnerError {
                if shouldRetryAfterAuthenticationError(error),
                   credentials.source.supportsRefresh,
                   credentials.oauth.refreshToken != nil {
                    credentials = try await apiClient.refreshToken(credentials, credentialLoader)
                    usage = try await apiClient.fetchUsage(credentials.oauth.accessToken)
                } else {
                    throw error
                }
            }
            return ProviderSnapshot(
                provider: .claude,
                fiveHour: UsageWindow(
                    kind: .fiveHour,
                    usedPercentage: usage.fiveHour?.utilization,
                    resetsAt: parseISODate(usage.fiveHour?.resetsAt),
                    message: usage.fiveHour == nil ? "No 5h limit returned." : nil
                ),
                weekly: UsageWindow(
                    kind: .weekly,
                    usedPercentage: usage.sevenDay?.utilization,
                    resetsAt: parseISODate(usage.sevenDay?.resetsAt),
                    message: usage.sevenDay == nil ? "No weekly limit returned." : nil
                ),
                detail: detailText(from: credentials, accountInfo: accountInfo)
            )
        } catch {
            let message = error.localizedDescription
            return ProviderSnapshot(
                provider: .claude,
                fiveHour: UsageWindow(kind: .fiveHour, usedPercentage: nil, resetsAt: nil, message: message),
                weekly: UsageWindow(kind: .weekly, usedPercentage: nil, resetsAt: nil, message: message),
                detail: nil
            )
        }
    }

    static func liveFetchStatus() async throws -> ClaudeAuthStatus {
        let output = try await ProcessRunner.run(
            executable: "claude",
            arguments: ["auth", "status", "--json"],
            timeout: 10
        )
        return try JSONDecoder().decode(ClaudeAuthStatus.self, from: Data(output.utf8))
    }

    static func liveRefreshToken(
        _ credentials: ClaudeCredentialResult,
        credentialLoader: ClaudeCredentialLoader
    ) async throws -> ClaudeCredentialResult {
        guard let refreshToken = credentials.oauth.refreshToken else {
            return credentials
        }

        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
            "scope": "user:profile user:inference user:sessions:claude_code",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProcessRunnerError.invalidResponse("Claude refresh endpoint returned an invalid response.")
        }

        if http.statusCode == 400 || http.statusCode == 401 {
            if let payload = try? JSONDecoder().decode(ClaudeRefreshErrorResponse.self, from: data),
               payload.error == "invalid_grant" {
                throw ProcessRunnerError.invalidResponse("Claude session expired; log in again.")
            }
            throw ProcessRunnerError.invalidResponse("Claude session expired; log in again.")
        }

        guard (200 ..< 300).contains(http.statusCode) else {
            throw ProcessRunnerError.invalidResponse("Claude token refresh failed with HTTP \(http.statusCode).")
        }

        let payload = try JSONDecoder().decode(ClaudeRefreshResponse.self, from: data)
        guard let accessToken = payload.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines), !accessToken.isEmpty else {
            throw ProcessRunnerError.invalidResponse("Claude token refresh returned no access token.")
        }

        var updated = credentials
        updated.oauth.accessToken = accessToken
        if let refreshToken = payload.refreshToken {
            updated.oauth.refreshToken = refreshToken
        }
        if let expiresIn = payload.expiresIn {
            updated.oauth.expiresAt = Date().timeIntervalSince1970 * 1000 + Double(expiresIn) * 1000
        }
        credentialLoader.saveCredentials(updated)
        return updated
    }

    static func liveFetchUsage(with accessToken: String) async throws -> ClaudeUsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("AIPace", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProcessRunnerError.invalidResponse("Claude usage endpoint returned an invalid response.")
            }

            switch http.statusCode {
            case 200 ..< 300:
                return try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
            case 401, 403:
                throw ProcessRunnerError.invalidResponse("Claude authentication failed.")
            case 429:
                let now = Date()
                let rateLimitInfo = ClaudeRateLimitInfo(headers: http.allHeaderFields, now: now)
                throw ProcessRunnerError.invalidResponse(rateLimitInfo.message(now: now))
            default:
                throw ProcessRunnerError.invalidResponse("Claude usage endpoint returned HTTP \(http.statusCode).")
            }
        } catch let error as ProcessRunnerError {
            throw error
        } catch {
            throw ProcessRunnerError.invalidResponse("Claude usage request failed: \(error.localizedDescription)")
        }
    }

    func parseISODate(_ isoString: String?) -> Date? {
        guard let isoString else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: isoString)
    }

    func detailText(from credentials: ClaudeCredentialResult, accountInfo: ClaudeAccountInfo?) -> String? {
        let tier = credentials.oauth.subscriptionType
            .map(formatSubscriptionType(_:))
        let identity = accountInfo?.displayName ?? accountInfo?.email ?? accountInfo?.organizationName

        return [tier, identity].compactMap { $0 }.joined(separator: " · ").nilIfEmpty
    }

    func formatSubscriptionType(_ raw: String) -> String {
        switch raw.lowercased() {
        case "claude_max", "max":
            return "Max"
        case "claude_pro", "pro":
            return "Pro"
        case "api", "claude_api":
            return "API"
        default:
            return raw
        }
    }

    func shouldRetryAfterAuthenticationError(_ error: ProcessRunnerError) -> Bool {
        guard case .invalidResponse(let message) = error else {
            return false
        }
        return message == "Claude authentication failed."
    }
}

struct ClaudeAPIClient: Sendable {
    let fetchStatus: @Sendable () async throws -> ClaudeAuthStatus
    let refreshToken: @Sendable (ClaudeCredentialResult, ClaudeCredentialLoader) async throws -> ClaudeCredentialResult
    let fetchUsage: @Sendable (String) async throws -> ClaudeUsageResponse

    init(
        fetchStatus: @escaping @Sendable () async throws -> ClaudeAuthStatus = ClaudeProbe.liveFetchStatus,
        refreshToken: @escaping @Sendable (ClaudeCredentialResult, ClaudeCredentialLoader) async throws -> ClaudeCredentialResult = ClaudeProbe.liveRefreshToken,
        fetchUsage: @escaping @Sendable (String) async throws -> ClaudeUsageResponse = ClaudeProbe.liveFetchUsage(with:)
    ) {
        self.fetchStatus = fetchStatus
        self.refreshToken = refreshToken
        self.fetchUsage = fetchUsage
    }
}

struct ClaudeAuthStatus: Decodable, Sendable {
    let loggedIn: Bool?
}

struct ClaudeUsageResponse: Decodable, Sendable {
    let fiveHour: ClaudeQuotaData?
    let sevenDay: ClaudeQuotaData?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
    }
}

struct ClaudeQuotaData: Decodable, Sendable {
    let utilization: Double?
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

struct ClaudeRateLimitInfo: Equatable, Sendable {
    let retryAfter: Date?
    let resets: [ClaudeRateLimitReset]

    init(headers: [AnyHashable: Any], now: Date = Date()) {
        retryAfter = Self.parseRetryAfter(Self.headerValue("retry-after", in: headers), now: now)
        resets = Self.resetHeaders.compactMap { header, label in
            guard let value = Self.headerValue(header, in: headers),
                  let date = Self.parseRFC3339Date(value) else {
                return nil
            }
            return ClaudeRateLimitReset(label: label, date: date)
        }
    }

    init(retryAfter: Date? = nil, resets: [ClaudeRateLimitReset] = []) {
        self.retryAfter = retryAfter
        self.resets = resets
    }

    func message(now: Date = Date()) -> String {
        var parts = ["Claude usage endpoint returned HTTP 429."]

        if let retryAfter {
            parts.append("Retry after \(Self.compactDuration(until: retryAfter, now: now)).")
        }

        for reset in resets {
            parts.append("\(reset.label) reset in \(Self.compactDuration(until: reset.date, now: now)).")
        }

        return parts.joined(separator: " ")
    }

    private static let resetHeaders: [(header: String, label: String)] = [
        ("anthropic-ratelimit-requests-reset", "Requests"),
        ("anthropic-ratelimit-tokens-reset", "Tokens"),
        ("anthropic-ratelimit-input-tokens-reset", "Input tokens"),
        ("anthropic-ratelimit-output-tokens-reset", "Output tokens"),
    ]

    private static func headerValue(_ name: String, in headers: [AnyHashable: Any]) -> String? {
        for (rawKey, rawValue) in headers {
            let key = (rawKey as? String) ?? String(describing: rawKey)
            guard key.caseInsensitiveCompare(name) == .orderedSame else {
                continue
            }

            let value = (rawValue as? String) ?? String(describing: rawValue)
            return value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        }

        return nil
    }

    private static func parseRetryAfter(_ value: String?, now: Date) -> Date? {
        guard let value else {
            return nil
        }

        if let seconds = TimeInterval(value), seconds.isFinite {
            return now.addingTimeInterval(max(0, seconds))
        }

        return parseHTTPDate(value)
    }

    private static func parseRFC3339Date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func parseHTTPDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in [
            "EEE',' dd MMM yyyy HH':'mm':'ss zzz",
            "EEEE',' dd'-'MMM'-'yy HH':'mm':'ss zzz",
            "EEE MMM d HH':'mm':'ss yyyy",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }

    private static func compactDuration(until date: Date, now: Date) -> String {
        let seconds = max(0, date.timeIntervalSince(now))

        if seconds < 60 {
            return "\(Int(ceil(seconds)))s"
        }

        let minutes = Int(ceil(seconds / 60))
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = Int(ceil(seconds / 3600))
        if hours < 24 {
            return "\(hours)h"
        }

        return "\(Int(ceil(seconds / 86400)))d"
    }
}

struct ClaudeRateLimitReset: Equatable, Sendable {
    let label: String
    let date: Date
}

struct ClaudeRefreshResponse: Decodable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct ClaudeRefreshErrorResponse: Decodable, Sendable {
    let error: String?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

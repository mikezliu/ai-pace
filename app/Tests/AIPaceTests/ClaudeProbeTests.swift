import Foundation
import Testing
@testable import AIPace

struct ClaudeProbeTests {
    @Test
    func fetchReturnsUsageSnapshotAndDetailText() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let credentialsURL = homeDirectory.appendingPathComponent(".claude/.credentials.json")
        try FileManager.default.createDirectory(at: credentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "token",
                "refreshToken": "refresh",
                "expiresAt": 9999999999999,
                "subscriptionType": "claude_max"
              }
            }
            """.utf8
        ).write(to: credentialsURL)

        let configURL = homeDirectory.appendingPathComponent(".claude.json")
        try Data(
            """
            {
              "oauthAccount": {
                "displayName": "Ada Lovelace"
              }
            }
            """.utf8
        ).write(to: configURL)

        let loader = ClaudeCredentialLoader(
            homeDirectory: homeDirectory,
            environment: [:],
            setupTokenStore: .empty,
            keychainLoadOverride: .success(nil)
        )
        let resolver = ClaudeAccountInfoResolver(configURL: configURL)
        let apiClient = ClaudeAPIClient(
            fetchStatus: { ClaudeAuthStatus(loggedIn: nil) },
            refreshToken: { credentials, _ in
                Issue.record("refreshToken should not be called for fresh credentials")
                return credentials
            },
            fetchUsage: { _ in
                ClaudeUsageResponse(
                    fiveHour: ClaudeQuotaData(utilization: 25, resetsAt: "2026-04-06T12:00:00Z"),
                    sevenDay: ClaudeQuotaData(utilization: 60, resetsAt: "2026-04-12T12:00:00Z")
                )
            }
        )

        let snapshot = await ClaudeProbe(
            credentialLoader: loader,
            accountInfoResolver: resolver,
            apiClient: apiClient
        ).fetch()

        #expect(snapshot.provider == .claude)
        #expect(snapshot.fiveHour.usedPercentage == 25)
        #expect(snapshot.weekly.usedPercentage == 60)
        #expect(snapshot.detail == "Max · Ada Lovelace")
        #expect(snapshot.fiveHour.message == nil)
        #expect(snapshot.weekly.message == nil)
    }

    @Test
    func fetchReportsLoggedInWhenCredentialsCannotBeRead() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let loader = ClaudeCredentialLoader(
            homeDirectory: homeDirectory,
            environment: [:],
            setupTokenStore: .empty,
            keychainLoadOverride: .success(nil)
        )
        let apiClient = ClaudeAPIClient(
            fetchStatus: { ClaudeAuthStatus(loggedIn: true) },
            refreshToken: { credentials, _ in credentials },
            fetchUsage: { _ in
                Issue.record("fetchUsage should not be called when credentials are missing")
                return ClaudeUsageResponse(fiveHour: nil, sevenDay: nil)
            }
        )

        let snapshot = await ClaudeProbe(
            credentialLoader: loader,
            accountInfoResolver: ClaudeAccountInfoResolver(configURL: homeDirectory.appendingPathComponent(".missing")),
            apiClient: apiClient
        ).fetch()

        #expect(snapshot.fiveHour.message == "Claude is logged in, but credentials could not be read from file, AIPace setup-token, environment, or Keychain.")
        #expect(snapshot.weekly.message == snapshot.fiveHour.message)
    }

    @Test
    func fetchUsesSetupTokenWithoutRefresh() async throws {
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let store = ClaudeSetupTokenStore(
            loadToken: { .success("setup-token") },
            saveToken: { _ in .success(()) },
            deleteToken: { .success(()) }
        )
        let loader = ClaudeCredentialLoader(
            homeDirectory: homeDirectory,
            environment: [:],
            setupTokenStore: store,
            keychainLoadOverride: .success(nil)
        )
        let apiClient = ClaudeAPIClient(
            fetchStatus: { ClaudeAuthStatus(loggedIn: nil) },
            refreshToken: { credentials, _ in
                Issue.record("refreshToken should not be called for setup-token credentials")
                return credentials
            },
            fetchUsage: { token in
                #expect(token == "setup-token")
                return ClaudeUsageResponse(
                    fiveHour: ClaudeQuotaData(utilization: 12, resetsAt: nil),
                    sevenDay: ClaudeQuotaData(utilization: 34, resetsAt: nil)
                )
            }
        )

        let snapshot = await ClaudeProbe(
            credentialLoader: loader,
            accountInfoResolver: ClaudeAccountInfoResolver(configURL: homeDirectory.appendingPathComponent(".missing")),
            apiClient: apiClient
        ).fetch()

        #expect(snapshot.fiveHour.usedPercentage == 12)
        #expect(snapshot.weekly.usedPercentage == 34)
    }

    @Test
    func rateLimitInfoParsesRetryAfterSecondsAndResetHeaders() {
        let now = ISO8601DateFormatter().date(from: "2026-06-11T04:00:00Z")!
        let headers: [AnyHashable: Any] = [
            "Retry-After": "90",
            "anthropic-ratelimit-requests-reset": "2026-06-11T04:03:00Z",
            "anthropic-ratelimit-tokens-reset": "2026-06-11T05:00:00Z",
            "anthropic-ratelimit-input-tokens-reset": "2026-06-11T04:00:30Z",
            "anthropic-ratelimit-output-tokens-reset": "2026-06-13T04:00:00Z",
        ]

        let message = ClaudeRateLimitInfo(headers: headers, now: now).message(now: now)

        #expect(
            message == "Claude usage endpoint returned HTTP 429. Retry after 2m. Requests reset in 3m. Tokens reset in 1h. Input tokens reset in 30s. Output tokens reset in 2d."
        )
    }

    @Test
    func rateLimitInfoParsesRetryAfterHTTPDate() {
        let now = ISO8601DateFormatter().date(from: "2026-06-11T04:00:00Z")!
        let headers: [AnyHashable: Any] = [
            "retry-after": "Thu, 11 Jun 2026 04:05:00 GMT",
        ]

        let message = ClaudeRateLimitInfo(headers: headers, now: now).message(now: now)

        #expect(message == "Claude usage endpoint returned HTTP 429. Retry after 5m.")
    }

    @Test
    func rateLimitInfoFallsBackWhenHeadersAreMissing() {
        let now = ISO8601DateFormatter().date(from: "2026-06-11T04:00:00Z")!

        let message = ClaudeRateLimitInfo(headers: [:], now: now).message(now: now)

        #expect(message == "Claude usage endpoint returned HTTP 429.")
    }

    @Test
    func fetchRetriesAfterAuthenticationFailureForRefreshableCredentials() async throws {
        actor State {
            var usageTokens: [String] = []
            var refreshCalls = 0

            func recordUsageToken(_ token: String) -> Int {
                usageTokens.append(token)
                return usageTokens.count
            }

            func recordRefresh() {
                refreshCalls += 1
            }
        }

        let state = State()
        let homeDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: homeDirectory) }

        let credentialsURL = homeDirectory.appendingPathComponent(".claude/.credentials.json")
        try FileManager.default.createDirectory(at: credentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(
            """
            {
              "claudeAiOauth": {
                "accessToken": "old-token",
                "refreshToken": "refresh-token",
                "expiresAt": 9999999999999
              }
            }
            """.utf8
        ).write(to: credentialsURL)

        let loader = ClaudeCredentialLoader(
            homeDirectory: homeDirectory,
            environment: [:],
            setupTokenStore: .empty,
            keychainLoadOverride: .success(nil)
        )
        let apiClient = ClaudeAPIClient(
            fetchStatus: { ClaudeAuthStatus(loggedIn: nil) },
            refreshToken: { credentials, _ in
                await state.recordRefresh()
                var updated = credentials
                updated.oauth.accessToken = "new-token"
                return updated
            },
            fetchUsage: { token in
                let call = await state.recordUsageToken(token)
                if call == 1 {
                    throw ProcessRunnerError.invalidResponse("Claude authentication failed.")
                }
                return ClaudeUsageResponse(
                    fiveHour: ClaudeQuotaData(utilization: 30, resetsAt: "2026-04-06T12:00:00Z"),
                    sevenDay: ClaudeQuotaData(utilization: 55, resetsAt: "2026-04-12T12:00:00Z")
                )
            }
        )

        let snapshot = await ClaudeProbe(
            credentialLoader: loader,
            accountInfoResolver: ClaudeAccountInfoResolver(configURL: homeDirectory.appendingPathComponent(".missing")),
            apiClient: apiClient
        ).fetch()

        #expect(snapshot.fiveHour.usedPercentage == 30)
        #expect(snapshot.weekly.usedPercentage == 55)
        let usageTokens = await state.usageTokens
        let refreshCalls = await state.refreshCalls
        #expect(usageTokens == ["old-token", "new-token"])
        #expect(refreshCalls == 1)
    }
}

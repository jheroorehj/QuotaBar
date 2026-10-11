import Foundation
import Testing
@testable import QuotaBarCore

@Suite("Claude")
struct ClaudeTests {
    static let credentials = """
    {"claudeAiOauth": {"accessToken": "sk-ant-oat01-test", "refreshToken": "sk-ant-ort01-test",
     "expiresAt": 1791450000000, "scopes": ["user:inference", "user:profile"],
     "subscriptionType": "max", "rateLimitTier": "default_claude_max_5x"}}
    """

    static let legacyUsage = """
    {"five_hour": {"utilization": 35.0, "resets_at": "2026-10-08T05:00:00.512345+00:00"},
     "seven_day": {"utilization": 12.5, "resets_at": "2026-10-13T03:00:00+00:00"},
     "seven_day_oauth_apps": null,
     "seven_day_opus": {"utilization": 3.0, "resets_at": null},
     "seven_day_sonnet": null,
     "extra_usage": {"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null}}
    """

    static let limitsUsage = """
    {"five_hour": null, "seven_day": null, "seven_day_opus": null,
     "limits": [
       {"kind": "session", "group": "session", "percent": 42, "resets_at": "2026-10-08T05:00:00Z", "scope": null, "is_active": true},
       {"kind": "weekly_all", "group": "weekly", "percent": 18, "resets_at": "2026-10-13T03:00:00Z"},
       {"kind": "weekly_scoped", "group": "weekly", "percent": 5, "resets_at": "2026-10-13T03:00:00Z",
        "scope": {"model": {"id": "claude-opus", "display_name": "Opus"}}},
       {"kind": "weekly_scoped", "group": "weekly", "percent": 90, "is_active": false,
        "scope": {"model": {"display_name": "Promo"}}}
     ],
     "extra_usage": {"is_enabled": true, "monthly_limit": 5000, "used_credits": 1250, "utilization": 25}}
    """

    @Test func parsesCredentialsAndPlan() throws {
        let credentials = try ClaudeOAuthCredentials.parse(Data(Self.credentials.utf8))
        #expect(credentials.accessToken == "sk-ant-oat01-test")
        #expect(credentials.planName == "Max 5x")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_791_450_000))
        #expect(!credentials.isExpired(now: fixedNow))
        #expect(credentials.isExpired(now: Date(timeIntervalSince1970: 1_791_450_000)))
    }

    @Test func planNames() {
        func plan(_ type: String?, _ tier: String?) -> String? {
            ClaudeOAuthCredentials(accessToken: "x", expiresAt: nil, subscriptionType: type, rateLimitTier: tier).planName
        }
        #expect(plan("max", "default_claude_max_20x") == "Max 20x")
        #expect(plan("max", nil) == "Max")
        #expect(plan("pro", "default_claude_ai") == "Pro")
        #expect(plan(nil, nil) == nil)
    }

    @Test func missingTokenRequiresLogin() {
        #expect(throws: ProviderError.self) {
            try ClaudeOAuthCredentials.parse(Data(#"{"mcpOAuth": {}}"#.utf8))
        }
    }

    @Test func legacyUsageShape() throws {
        let windows = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(Self.legacyUsage.utf8)).windows()
        #expect(windows.map(\.id) == ["session", "weekly", "weekly.opus"])
        #expect(windows[0].label == "5시간")
        #expect(windows[0].usedPercent == 35)
        #expect(windows[0].resetsAt == date("2026-10-08T05:00:00Z"))
        #expect(windows[1].label == "주간")
        #expect(windows[2].label == "주간 · Opus")
        #expect(windows[2].resetsAt == nil)
    }

    @Test func limitsArrayShape() throws {
        let windows = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(Self.limitsUsage.utf8)).windows()
        #expect(windows.map(\.id) == ["session", "weekly", "weekly.opus", "extra"])
        #expect(windows.map(\.usedPercent) == [42, 18, 5, 25])
        #expect(windows[2].label == "주간 · Opus")
        #expect(windows[3].detail == "$12.50 / $50.00")
    }

    @Test func providerFetchesWithCredentialsFile() async throws {
        let home = try TemporaryDirectory()
        try home.write(".claude/.credentials.json", Self.credentials)
        let http = MockHTTPClient(json: Self.legacyUsage)
        let provider = ClaudeSubscriptionProvider(context: makeContext(home: home, http: http))

        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.plan == "Max 5x")
        #expect(snapshot.windows.count == 3)
        #expect(snapshot.source == "OAuth API")
        #expect(snapshot.highestUsedPercent == 35)

        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    }

    @Test func customConfigDirectory() async throws {
        let home = try TemporaryDirectory()
        try home.write("work-claude/.credentials.json", Self.credentials)
        let context = makeContext(
            home: home,
            values: ["CLAUDE_CONFIG_DIR": home.url.appendingPathComponent("work-claude").path],
            http: MockHTTPClient(json: Self.limitsUsage)
        )
        let snapshot = try await ClaudeSubscriptionProvider(context: context).fetchUsage()
        #expect(snapshot.windows.first?.usedPercent == 42)
    }

    @Test func missingCredentialsAsksForLogin() async throws {
        let home = try TemporaryDirectory()
        let provider = ClaudeSubscriptionProvider(context: makeContext(home: home))
        await #expect(throws: ProviderError.setupRequired(ClaudeSubscriptionProvider.loginHint)) {
            try await provider.fetchUsage()
        }
    }

    @Test func expiredTokenWithoutCLIAsksToRunClaude() async throws {
        let home = try TemporaryDirectory()
        try home.write(".claude/.credentials.json", Self.credentials)
        let later = Date(timeIntervalSince1970: 1_791_460_000)
        let provider = ClaudeSubscriptionProvider(context: makeContext(home: home, now: later))
        await #expect(throws: ProviderError.authExpired(ClaudeSubscriptionProvider.expiredHint)) {
            try await provider.fetchUsage()
        }
    }

    @Test func expiredTokenIsRefreshedThroughCLI() async throws {
        let home = try TemporaryDirectory()
        let credentialsFile = try home.write(".claude/.credentials.json", Self.credentials)
        // 가짜 claude: `auth status` 가 실행되면 만료 시각이 늦춰진 토큰을 저장한다 (Claude Code 의 갱신 흉내).
        let refreshed = Self.credentials
            .replacingOccurrences(of: "1791450000000", with: "1791500000000")
            .replacingOccurrences(of: "sk-ant-oat01-test", with: "sk-ant-oat01-new")
        try home.write("refreshed.json", refreshed)
        try home.writeScript("claude", """
        [ "$1" = "auth" ] && [ "$2" = "status" ] && cp "\(home.url.path)/refreshed.json" "\(credentialsFile.path)"
        echo '{"loggedIn": true}'
        """)
        let http = MockHTTPClient(json: Self.legacyUsage)
        let later = Date(timeIntervalSince1970: 1_791_460_000)
        let snapshot = try await ClaudeSubscriptionProvider(context: makeContext(home: home, http: http, now: later)).fetchUsage()
        #expect(snapshot.windows.count == 3)
        #expect(http.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer sk-ant-oat01-new")
    }

    @Test func rateLimitAndServerErrors() async throws {
        let home = try TemporaryDirectory()
        try home.write(".claude/.credentials.json", Self.credentials)
        let limited = ClaudeSubscriptionProvider(context: makeContext(home: home, http: MockHTTPClient(status: 429, json: "{}")))
        await #expect(throws: ProviderError.rateLimited(retryAfter: nil)) {
            try await limited.fetchUsage()
        }
        let broken = ClaudeSubscriptionProvider(context: makeContext(home: home, http: MockHTTPClient(json: #"{"unexpected": true}"#)))
        await #expect(throws: ProviderError.invalidResponse("사용량 항목이 없습니다.")) {
            try await broken.fetchUsage()
        }
    }
}

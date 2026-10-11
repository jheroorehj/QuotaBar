import Foundation
import Testing
@testable import QuotaBarCore

@Suite("Codex")
struct CodexTests {
    static let auth = """
    {"OPENAI_API_KEY": null,
     "tokens": {"id_token": "x.y.z", "access_token": "codex-access", "refresh_token": "codex-refresh", "account_id": "acct_123"},
     "last_refresh": "2026-10-07T00:00:00Z"}
    """

    static let webUsage = """
    {"plan_type": "plus",
     "rate_limit": {"allowed": true, "limit_reached": false,
       "primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_after_seconds": 14460, "reset_at": 1791432060},
       "secondary_window": {"used_percent": 82, "limit_window_seconds": 604800, "reset_after_seconds": 400000, "reset_at": 1791817600}},
     "credits": {"has_credits": false, "unlimited": false, "balance": "0"},
     "additional_rate_limits": [
       {"limit_name": "GPT-5.3-Codex-Spark", "metered_feature": "codex_bengalfox",
        "rate_limit": {"primary_window": {"used_percent": 4, "limit_window_seconds": 18000, "reset_at": 1791432060},
                       "secondary_window": null}}]}
    """

    static let rpcResult = """
    {"rateLimits": {"limitId": "codex",
      "primary": {"usedPercent": 21.5, "windowDurationMins": 300, "resetsAt": 1791432060},
      "secondary": {"usedPercent": 40.0, "windowDurationMins": 10080, "resetsAt": 1791817600},
      "credits": {"hasCredits": false, "unlimited": false, "balance": null},
      "planType": "pro"}}
    """

    @Test func parsesAuth() throws {
        let auth = try CodexAuth.parse(Data(Self.auth.utf8))
        #expect(auth.accessToken == "codex-access")
        #expect(auth.accountID == "acct_123")
    }

    @Test func accountIDFromIDTokenClaim() throws {
        let payload = #"{"https://api.openai.com/auth": {"chatgpt_account_id": "acct_jwt"}}"#
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let json = #"{"tokens": {"access_token": "a", "id_token": "h.\#(encoded).s"}}"#
        #expect(try CodexAuth.parse(Data(json.utf8)).accountID == "acct_jwt")
    }

    @Test func apiKeyOnlyLoginIsRejected() {
        #expect(throws: ProviderError.setupRequired(CodexSubscriptionProvider.loginHint)) {
            try CodexAuth.parse(Data(#"{"OPENAI_API_KEY": "sk-proj-x", "tokens": null}"#.utf8))
        }
    }

    @Test func webUsageWindows() throws {
        let snapshot = try CodexSubscriptionProvider.makeWebSnapshot(data: Data(Self.webUsage.utf8), fetchedAt: fixedNow)
        #expect(snapshot.plan == "Plus")
        #expect(snapshot.windows.map(\.label) == ["5시간", "주간", "5시간 · GPT-5.3-Codex-Spark"])
        #expect(snapshot.windows.map(\.usedPercent) == [12, 82, 4])
        #expect(snapshot.windows[0].resetsAt == Date(timeIntervalSince1970: 1_791_432_060))
        #expect(snapshot.windows[1].id == "weekly")
    }

    @Test func rpcWindows() throws {
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(Self.rpcResult.utf8))
        let snapshot = try CodexSubscriptionProvider.makeRPCSnapshot(result: result, fetchedAt: fixedNow)
        #expect(snapshot.plan == "Pro")
        #expect(snapshot.windows.map(\.id) == ["session", "weekly"])
        #expect(snapshot.windows.map(\.usedPercent) == [21.5, 40])
        #expect(snapshot.source == "codex app-server")
    }

    @Test func providerUsesWebAPI() async throws {
        let home = try TemporaryDirectory()
        try home.write(".codex/auth.json", Self.auth)
        let http = MockHTTPClient(json: Self.webUsage)
        let snapshot = try await CodexSubscriptionProvider(context: makeContext(home: home, http: http)).fetchUsage()
        #expect(snapshot.windows.count == 3)
        let request = try #require(http.requests.first)
        #expect(request.url?.absoluteString == "https://chatgpt.com/backend-api/wham/usage")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer codex-access")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct_123")
    }

    @Test func respectsCodexHome() async throws {
        let home = try TemporaryDirectory()
        try home.write("work/auth.json", Self.auth)
        let context = makeContext(
            home: home,
            values: ["CODEX_HOME": home.url.appendingPathComponent("work").path],
            http: MockHTTPClient(json: Self.webUsage)
        )
        let snapshot = try await CodexSubscriptionProvider(context: context).fetchUsage()
        #expect(snapshot.plan == "Plus")
    }

    @Test func fallsBackToAppServerWhenTokenRejected() async throws {
        let home = try TemporaryDirectory()
        try home.write(".codex/auth.json", Self.auth)
        let rpcLine = Self.rpcResult.replacingOccurrences(of: "\n", with: " ")
        // 가짜 codex app-server: initialize 와 account/rateLimits/read 에 응답한다. (jsonrpc 필드 없음)
        try home.writeScript("codex", """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/^{"id":\\([0-9]*\\),.*/\\1/p')
          case "$line" in
            *'"method":"initialize"'*) printf '{"id":%s,"result":{"userAgent":"codex"}}\\n' "$id" ;;
            *'"method":"account/rateLimits/read"'*) printf '{"id":%s,"result":%s}\\n' "$id" '\(rpcLine)' ;;
          esac
        done
        """)
        let http = MockHTTPClient(status: 401, json: #"{"detail": "expired"}"#)
        let snapshot = try await CodexSubscriptionProvider(context: makeContext(home: home, http: http)).fetchUsage()
        #expect(snapshot.source == "codex app-server")
        #expect(snapshot.windows.map(\.usedPercent) == [21.5, 40])
    }

    @Test func expiredWithoutCLI() async throws {
        let home = try TemporaryDirectory()
        try home.write(".codex/auth.json", Self.auth)
        let provider = CodexSubscriptionProvider(context: makeContext(home: home, http: MockHTTPClient(status: 401, json: "{}")))
        await #expect(throws: ProviderError.authExpired(CodexSubscriptionProvider.expiredHint)) {
            try await provider.fetchUsage()
        }
    }

    @Test func missingAuthFile() async throws {
        let home = try TemporaryDirectory()
        let provider = CodexSubscriptionProvider(context: makeContext(home: home))
        await #expect(throws: ProviderError.setupRequired(CodexSubscriptionProvider.loginHint)) {
            try await provider.fetchUsage()
        }
    }
}

import Foundation
import Testing
@testable import QuotaBarCore

private let agyTimeoutOutput = #"""
error: Eligibility check failed: failed to get profile picture: dial tcp 142.250.23.132:443: i/o timeout
{"conversation_id":"","status":"ERROR","response":"","error":"Eligibility check failed: failed to get profile picture: dial tcp 142.250.23.132:443: i/o timeout","duration_seconds":0,"num_turns":0}
"""#

@Suite("Antigravity 실패 응답")
struct AntigravityFailureTests {
    /// agy 1.x 가 일시적인 네트워크 오류로 실패했을 때의 실제 출력 (2026-10-08).
    @Test func errorStatusSurfacesReason() {
        #expect(throws: ProviderError.commandFailed("agy: Eligibility check failed: failed to get profile picture: dial tcp 142.250.23.132:443: i/o timeout")) {
            try AntigravityUsageReport.parse(Data(agyTimeoutOutput.utf8))
        }
    }
}

@Suite("Gemini")
struct GeminiTests {
    static let agyReport = """
    {"conversation_id": "", "status": "SUCCESS", "response": "", "duration_seconds": 0, "num_turns": 0,
     "usage": {"input_tokens": 0, "output_tokens": 0, "total_tokens": 0},
     "command": {"name": "usage", "data": {"description": "Models share limits", "groups": [
       {"name": "Gemini Models", "buckets": [
         {"id": "gemini-weekly", "name": "Weekly Limit Remaining", "window": "weekly", "remaining_fraction": 0.86, "reset_time": "2026-10-13T18:40:27Z"},
         {"id": "gemini-5h", "name": "Five Hour Limit Remaining", "window": "5h", "remaining_fraction": 0.95, "reset_time": "2026-10-08T03:48:04Z"}]},
       {"name": "Claude and GPT models", "buckets": [
         {"id": "3p-weekly", "name": "Weekly Limit Remaining", "window": "weekly", "remaining_fraction": 0.89, "reset_time": "2026-10-13T02:38:46Z"},
         {"id": "3p-5h", "name": "Five Hour Limit Remaining", "window": "5h", "remaining_fraction": 1.0, "reset_time": "2026-10-08T05:29:19Z"},
         {"id": "3p-disabled", "window": "5h", "remaining_fraction": 0.1, "disabled": true}]}]}}}
    """

    static let quota = """
    {"buckets": [
      {"remainingAmount": "1400", "remainingFraction": 0.93, "resetTime": "2026-10-09T00:00:00Z", "tokenType": "REQUESTS", "modelId": "gemini-2.5-pro"},
      {"remainingFraction": 0.90, "resetTime": "2026-10-09T00:00:00Z", "tokenType": "REQUESTS", "modelId": "gemini-2.5-pro"},
      {"remainingFraction": 0.99, "resetTime": "2026-10-09T00:00:00Z", "tokenType": "REQUESTS", "modelId": "gemini-2.5-flash"}]}
    """

    @Test func parsesAntigravityReport() throws {
        let windows = try AntigravityUsageReport.parse(Data(Self.agyReport.utf8), includeThirdParty: true)
        #expect(windows.map(\.label) == ["5시간 · Gemini", "5시간 · Claude·GPT", "주간 · Gemini", "주간 · Claude·GPT"])
        // 기본값: Gemini 모델 한도만, 다른 서비스처럼 기간 이름만 쓴다.
        let geminiOnly = try AntigravityUsageReport.parse(Data(Self.agyReport.utf8))
        #expect(geminiOnly.map(\.label) == ["5시간", "주간"])
        #expect(abs(windows[0].usedPercent - 5) < 0.0001)
        #expect(windows[1].usedPercent == 0)
        #expect(abs(windows[2].usedPercent - 14) < 0.0001)
        #expect(windows[2].resetsAt == date("2026-10-13T18:40:27Z"))
    }

    @Test func antigravityReportToleratesLogLines() throws {
        let noisy = "Starting language server...\n" + Self.agyReport + "\nbye\n"
        #expect(try AntigravityUsageReport.parse(Data(noisy.utf8), includeThirdParty: true).count == 4)
    }

    @Test func rejectsUnsuccessfulReport() {
        let failed = Self.agyReport.replacingOccurrences(of: #""status": "SUCCESS""#, with: #""status": "ERROR""#)
        #expect(throws: ProviderError.self) { try AntigravityUsageReport.parse(Data(failed.utf8)) }
        #expect(throws: ProviderError.self) { try AntigravityUsageReport.parse(Data("not json".utf8)) }
    }

    @Test func parsesGeminiCLIQuota() throws {
        let windows = try GeminiCodeAssistAPI.parseQuota(Data(Self.quota.utf8))
        #expect(windows.map(\.label) == ["일간 · 2.5 Pro", "일간 · 2.5 Flash"])
        // 같은 모델의 버킷 중 가장 적게 남은 값(0.90)을 쓴다.
        #expect(abs(windows[0].usedPercent - 10) < 0.0001)
        #expect(abs(windows[1].usedPercent - 1) < 0.0001)
    }

    @Test func parsesLoadCodeAssist() throws {
        let paid = try GeminiCodeAssistAPI.parseLoadCodeAssist(Data("""
        {"currentTier": {"id": "standard-tier", "name": "Gemini Code Assist Standard"},
         "paidTier": {"id": "g1-pro-tier", "name": "Google AI Pro"},
         "cloudaicompanionProject": "my-project-123"}
        """.utf8))
        #expect(paid == .init(projectID: "my-project-123", plan: "Google AI Pro"))

        let object = try GeminiCodeAssistAPI.parseLoadCodeAssist(Data("""
        {"currentTier": {"id": "free-tier"}, "cloudaicompanionProject": {"id": "proj-obj", "name": "projects/proj-obj"}}
        """.utf8))
        #expect(object == .init(projectID: "proj-obj", plan: "Free"))
    }

    @Test func extractsOAuthClientFromScript() {
        let script = """
        const OAUTH_CLIENT_ID = '123-abc.apps.googleusercontent.com';
        // The client secret is not treated as a secret for installed apps.
        const OAUTH_CLIENT_SECRET = 'TEST-secret_value';
        """
        let client = GeminiCodeAssistAPI.extractClientCredentials(fromScript: script)
        #expect(client?.id == "123-abc.apps.googleusercontent.com")
        #expect(client?.secret == "TEST-secret_value")
        #expect(GeminiCodeAssistAPI.extractClientCredentials(fromScript: "nothing") == nil)
    }

    @Test func versionParsing() {
        #expect(GeminiSubscriptionProvider.parseVersion("1.2.11\n")! == (1, 2, 11))
        #expect(GeminiSubscriptionProvider.parseVersion("agy version v1.1.11 (darwin)")! == (1, 1, 11))
        #expect(GeminiSubscriptionProvider.parseVersion("unknown") == nil)
        #expect(GeminiSubscriptionProvider.isAtLeast((1, 1, 11), (1, 1, 11)))
        #expect(GeminiSubscriptionProvider.isAtLeast((1, 2, 0), (1, 1, 11)))
        #expect(!GeminiSubscriptionProvider.isAtLeast((1, 1, 10), (1, 1, 11)))
        #expect(!GeminiSubscriptionProvider.isAtLeast((0, 9, 99), (1, 1, 11)))
    }

    /// 가짜 agy: --version 과 `-p /usage --output-format json` 에 응답한다.
    private func writeFakeAgy(in home: TemporaryDirectory, version: String = "1.2.11") throws {
        try home.write("agy-report.json", Self.agyReport)
        try home.writeScript("agy", """
        if [ "$1" = "--version" ]; then echo "\(version)"; exit 0; fi
        if [ "$1" = "-p" ] && [ "$2" = "/usage" ] && [ "$3" = "--output-format" ] && [ "$4" = "json" ]; then
          cat "\(home.url.path)/agy-report.json"; exit 0
        fi
        echo "unexpected args: $*" >&2; exit 3
        """)
    }

    @Test func providerUsesAntigravityCLI() async throws {
        let home = try TemporaryDirectory()
        try writeFakeAgy(in: home)
        let snapshot = try await GeminiSubscriptionProvider(context: makeContext(home: home)).fetchUsage()
        #expect(snapshot.source == "Antigravity CLI")
        #expect(snapshot.windows.map(\.label) == ["5시간", "주간"])
    }

    @Test func refusesOldAgyThatMightSpendQuota() async throws {
        let home = try TemporaryDirectory()
        try writeFakeAgy(in: home, version: "1.1.9")
        let provider = GeminiSubscriptionProvider(context: makeContext(home: home))
        await #expect(throws: ProviderError.self) { try await provider.fetchUsage() }
    }

    @Test func autoWithoutAnythingAsksForAntigravity() async throws {
        let home = try TemporaryDirectory()
        let provider = GeminiSubscriptionProvider(context: makeContext(home: home))
        await #expect(throws: ProviderError.setupRequired(GeminiSubscriptionProvider.antigravityHint)) {
            try await provider.fetchUsage()
        }
    }

    @Test func geminiCLISourceWithValidToken() async throws {
        let home = try TemporaryDirectory()
        try home.write(".gemini/oauth_creds.json", """
        {"access_token": "ya29.token", "refresh_token": "1//refresh", "expiry_date": 1791500000000}
        """)
        try home.write(".gemini/settings.json", #"{"security": {"auth": {"selectedType": "oauth-personal"}}}"#)
        let http = MockHTTPClient { request in
            if request.url?.absoluteString.hasSuffix("loadCodeAssist") == true {
                return (200, Data(#"{"currentTier": {"id": "standard-tier"}, "cloudaicompanionProject": "p-1"}"#.utf8))
            }
            return (200, Data(GeminiTests.quota.utf8))
        }
        let context = makeContext(home: home, values: ["QUOTABAR_GEMINI_SOURCE": "gemini-cli"], http: http)
        let snapshot = try await GeminiSubscriptionProvider(context: context).fetchUsage()
        #expect(snapshot.plan == "Standard")
        #expect(snapshot.windows.count == 2)
        #expect(http.requests.count == 2)
        let quotaBody = try #require(http.requests.last?.httpBody)
        #expect(String(decoding: quotaBody, as: UTF8.self) == #"{"project":"p-1"}"#)
    }

    @Test func geminiCLIConsumerShutdownExplainsMigration() async throws {
        let home = try TemporaryDirectory()
        try home.write(".gemini/oauth_creds.json", #"{"access_token": "ya29.token", "expiry_date": 1791500000000}"#)
        let http = MockHTTPClient(status: 403, json: #"{"error": {"message": "This client is no longer supported for Gemini Code Assist for individuals. Use Antigravity."}}"#)
        let context = makeContext(home: home, values: ["QUOTABAR_GEMINI_SOURCE": "gemini-cli"], http: http)
        await #expect(throws: ProviderError.setupRequired(GeminiSubscriptionProvider.consumerShutdownHint)) {
            try await GeminiSubscriptionProvider(context: context).fetchUsage()
        }
    }

    @Test func geminiCLIRefreshesExpiredTokenInMemory() async throws {
        let home = try TemporaryDirectory()
        let credsJSON = #"{"access_token": "old", "refresh_token": "1//refresh", "expiry_date": 1791400000000}"#
        let credsFile = try home.write(".gemini/oauth_creds.json", credsJSON)
        let http = MockHTTPClient { request in
            let url = request.url?.absoluteString ?? ""
            if url.contains("oauth2.googleapis.com/token") {
                return (200, Data(#"{"access_token": "fresh", "expires_in": 3599}"#.utf8))
            }
            if url.hasSuffix("loadCodeAssist") {
                return (200, Data(#"{"currentTier": {"id": "free-tier"}}"#.utf8))
            }
            return (200, Data(GeminiTests.quota.utf8))
        }
        let context = makeContext(
            home: home,
            values: [
                "QUOTABAR_GEMINI_SOURCE": "gemini-cli",
                "GEMINI_OAUTH_CLIENT_ID": "client.apps.googleusercontent.com",
                "GEMINI_OAUTH_CLIENT_SECRET": "secret+/=",
            ],
            http: http
        )
        let provider = GeminiSubscriptionProvider(context: context)
        _ = try await provider.fetchUsage()
        let tokenBody = String(decoding: try #require(http.requests.first?.httpBody), as: UTF8.self)
        #expect(tokenBody.contains("grant_type=refresh_token"))
        #expect(tokenBody.contains("client_secret=secret%2B%2F%3D"))
        #expect(http.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer fresh")

        // 두 번째 조회는 메모리에 보관한 토큰을 재사용한다.
        _ = try await provider.fetchUsage()
        #expect(http.requests.filter { $0.url?.absoluteString.contains("token") == true }.count == 1)
        // Gemini CLI 의 파일은 수정하지 않는다.
        #expect(try String(contentsOf: credsFile, encoding: .utf8) == credsJSON)
    }

    @Test func apiKeyAuthTypeIsExplained() async throws {
        let home = try TemporaryDirectory()
        try home.write(".gemini/oauth_creds.json", #"{"access_token": "t"}"#)
        try home.write(".gemini/settings.json", #"{"selectedAuthType": "gemini-api-key"}"#)
        let context = makeContext(home: home, values: ["QUOTABAR_GEMINI_SOURCE": "gemini-cli"])
        await #expect(throws: ProviderError.self) {
            try await GeminiSubscriptionProvider(context: context).fetchUsage()
        }
    }
}

@Suite("Antigravity 재시도")
struct AntigravityRetryTests {
    /// 첫 실행은 프로필 사진 시간 초과로 실패하고 두 번째 실행에서 성공하는 가짜 agy.
    @Test func retriesTransientStartupFailure() async throws {
        let home = try TemporaryDirectory()
        let counter = home.url.appendingPathComponent("count").path
        try home.writeScript("agy", """
        [ "$1" = "--version" ] && { echo "1.3.1"; exit 0; }
        n=$(cat '\(counter)' 2>/dev/null || echo 0); echo $((n + 1)) > '\(counter)'
        if [ "$n" = "0" ]; then
          echo '{"status":"ERROR","error":"Eligibility check failed: failed to get profile picture: dial tcp 142.250.23.132:443: i/o timeout"}'
        else
          echo '{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5}]}]}}}'
        fi
        """)
        let snapshot = try await GeminiSubscriptionProvider(context: makeContext(home: home)).fetchUsage()
        #expect(snapshot.windows.map(\.usedPercent) == [50])
        #expect(try String(contentsOfFile: counter, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "2")
    }
}

@Suite("Antigravity 사용량 API 직접 호출")
struct AntigravityDirectTests {
    /// `retrieveUserQuotaSummary` 의 실제 응답 (2026-10-08, Google AI Pro 계정).
    static let summary = """
    {"groups": [
      {"buckets": [
         {"bucketId": "gemini-weekly", "displayName": "Weekly Limit Remaining", "window": "weekly",
          "resetTime": "2026-10-08T08:37:15Z", "description": "You have used some of your weekly limit.", "remainingFraction": 0.75},
         {"bucketId": "gemini-5h", "displayName": "Five Hour Limit Remaining", "window": "5h",
          "resetTime": "2026-10-08T11:28:09Z", "remainingFraction": 1}],
       "displayName": "Gemini Models", "description": "Models within this group: Gemini Flash, Gemini Pro"},
      {"buckets": [
         {"bucketId": "3p-weekly", "displayName": "Weekly Limit Remaining", "window": "weekly",
          "resetTime": "2026-10-15T06:28:09Z", "remainingFraction": 1},
         {"bucketId": "3p-5h", "displayName": "Five Hour Limit Remaining", "window": "5h",
          "resetTime": "2026-10-08T11:28:09Z", "remainingFraction": 0.5}],
       "displayName": "Claude and GPT models", "description": "Models within this group: Claude Opus, Claude Sonnet, GPT-OSS"}],
     "description": "Within each group, models share a weekly limit and a 5-hour limit."}
    """

    static func keychainText(expiry: String) -> String {
        let json = #"{"token":{"access_token":"ya29.test","token_type":"Bearer","refresh_token":"r","expiry":"\#(expiry)"},"auth_method":"consumer","id_token":"x"}"#
        return "go-keyring-base64:" + Data(json.utf8).base64EncodedString() + "\n"
    }

    @Test func parsesSummary() throws {
        let geminiOnly = try AntigravityUsageReport.parseSummary(Data(Self.summary.utf8))
        #expect(geminiOnly.map(\.label) == ["5시간", "주간"])
        #expect(geminiOnly.map(\.usedPercent) == [0, 25])
        #expect(geminiOnly[1].resetsAt == date("2026-10-08T08:37:15Z"))
        let all = try AntigravityUsageReport.parseSummary(Data(Self.summary.utf8), includeThirdParty: true)
        #expect(all.map(\.label) == ["5시간 · Gemini", "5시간 · Claude·GPT", "주간 · Gemini", "주간 · Claude·GPT"])
    }

    @Test func parsesStoredToken() throws {
        let token = try #require(AntigravityStoredToken.parse(Self.keychainText(expiry: "2026-10-08T15:34:12.165885+09:00")))
        #expect(token.accessToken == "ya29.test")
        let expiresAt = try #require(token.expiresAt)
        #expect(abs(expiresAt.timeIntervalSince(date("2026-10-08T06:34:12Z"))) < 1)
        #expect(token.isUsable(now: date("2026-10-08T06:00:00Z")))
        #expect(!token.isUsable(now: date("2026-10-08T06:33:30Z")))
        #expect(AntigravityStoredToken.parse("not a keychain value") == nil)
    }

    @Test func shortensPlanName() {
        #expect(AntigravityQuotaAPI.shortPlanName("Google AI Pro") == "AI Pro")
        #expect(AntigravityQuotaAPI.shortPlanName("Antigravity") == "Antigravity")
        #expect(AntigravityQuotaAPI.shortPlanName(nil) == nil)
    }

    /// 토큰이 살아 있으면 agy 를 실행하지 않고 API 만 부른다.
    @Test func providerUsesAPIWithoutRunningCLI() async throws {
        let home = try TemporaryDirectory()
        try home.writeScript("agy", "echo ran >> '\(home.url.path)/agy-ran'; exit 1")
        let http = MockHTTPClient { request in
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer ya29.test")
            if request.url == AntigravityQuotaAPI.quotaSummaryURL {
                return (200, Data(Self.summary.utf8))
            }
            return (200, Data(#"{"currentTier":{"id":"free-tier","name":"Antigravity"},"paidTier":{"id":"g1-pro-tier","name":"Google AI Pro"}}"#.utf8))
        }
        var provider = GeminiSubscriptionProvider(context: makeContext(home: home, http: http, now: date("2026-10-08T06:00:00Z")))
        provider.antigravityKeychainReader = { Self.keychainText(expiry: "2026-10-08T15:34:12.165885+09:00") }
        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.source == "Antigravity API")
        #expect(snapshot.plan == "AI Pro")
        #expect(snapshot.windows.map(\.usedPercent) == [0, 25])
        #expect(!FileManager.default.fileExists(atPath: home.url.path + "/agy-ran"))
    }

    /// 토큰이 만료됐으면 CLI 로 넘어간다 (CLI 가 토큰을 갱신한다).
    @Test func expiredTokenFallsBackToCLI() async throws {
        let home = try TemporaryDirectory()
        try home.writeScript("agy", """
        [ "$1" = "--version" ] && { echo "1.3.1"; exit 0; }
        echo '{"status":"SUCCESS","command":{"name":"usage","data":{"groups":[{"name":"Gemini Models","buckets":[{"id":"gemini-weekly","window":"weekly","remaining_fraction":0.5}]}]}}}'
        """)
        var provider = GeminiSubscriptionProvider(context: makeContext(home: home, now: date("2026-10-08T07:00:00Z")))
        provider.antigravityKeychainReader = { Self.keychainText(expiry: "2026-10-08T15:34:12.165885+09:00") }
        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.source == "Antigravity CLI")
        #expect(snapshot.windows.map(\.usedPercent) == [50])
    }
}

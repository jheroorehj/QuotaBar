import Foundation
import Testing
@testable import QuotaBarCore

@Suite("Grok")
struct GrokTests {
    static let billing = """
    {"billingCycle": {"billingPeriodStart": "2026-10-06T00:00:00Z", "billingPeriodEnd": "2026-10-13T00:00:00Z"},
     "monthlyLimit": {"val": 5000}, "onDemandCap": {"val": 0}, "on_demand_enabled": false,
     "usage": {"includedUsed": {"val": 1250}, "onDemandUsed": {"val": 0}, "totalUsed": {"val": "1250"}}}
    """

    @Test func billingToWindow() throws {
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(Self.billing.utf8))
        let snapshot = try GrokSubscriptionProvider.makeSnapshot(result: result, fetchedAt: fixedNow)
        let window = try #require(snapshot.windows.first)
        #expect(window.label == "주간")
        #expect(window.usedPercent == 25)
        #expect(window.resetsAt == date("2026-10-13T00:00:00Z"))
        #expect(window.detail == "$12.50 / $50.00")
    }

    /// grok 1.0.46 의 실제 `_x.ai/billing` 응답 (2026-10-08, SuperGrok).
    static let unifiedBilling = """
    {"config": {"creditUsagePercent": 37.5,
                "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "2026-10-02T18:03:09.003810+00:00", "end": "2026-10-09T18:03:09.003810+00:00"},
                "onDemandCap": {"val": 0}, "onDemandUsed": {"val": 0}, "prepaidBalance": {"val": 0}, "isUnifiedBillingUser": true,
                "billingPeriodStart": "2026-10-02T18:03:09.003810+00:00", "billingPeriodEnd": "2026-10-09T18:03:09.003810+00:00"},
     "subscription_tier": "SuperGrok"}
    """

    @Test func unifiedBillingToWindow() throws {
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(Self.unifiedBilling.utf8))
        let snapshot = try GrokSubscriptionProvider.makeSnapshot(result: result, fetchedAt: fixedNow)
        let window = try #require(snapshot.windows.first)
        #expect(snapshot.plan == "SuperGrok")
        #expect(window.label == "주간")
        #expect(window.usedPercent == 37.5)
        #expect(window.detail == nil)
        let resetsAt = try #require(window.resetsAt)
        #expect(abs(resetsAt.timeIntervalSince(date("2026-10-09T18:03:09Z"))) < 1)
    }

    @Test func unifiedBillingShowsOnDemandSpend() throws {
        let json = Self.unifiedBilling
            .replacingOccurrences(of: #""onDemandCap": {"val": 0}, "onDemandUsed": {"val": 0}"#, with: #""onDemandCap": {"val": 2000}, "onDemandUsed": {"val": "350"}"#)
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        let window = try #require(try GrokSubscriptionProvider.makeSnapshot(result: result, fetchedAt: fixedNow).windows.first)
        #expect(window.detail == "추가 사용 $3.50 / $20.00")
    }

    @Test func periodLabels() {
        #expect(GrokBillingResponse.periodLabel(minutes: 7 * 1440) == "주간")
        #expect(GrokBillingResponse.periodLabel(minutes: 30 * 1440) == "월간")
        #expect(GrokBillingResponse.periodLabel(minutes: 14 * 1440) == "14일")
        #expect(GrokBillingResponse.periodLabel(minutes: nil) == "사용량")
    }

    @Test func billingWithoutLimitIsInvalid() throws {
        let result = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"usage": {"totalUsed": {"val": 1}}}"#.utf8))
        #expect(throws: ProviderError.self) { try GrokSubscriptionProvider.makeSnapshot(result: result, fetchedAt: fixedNow) }
    }

    @Test func providerTalksToGrokAgent() async throws {
        let home = try TemporaryDirectory()
        try home.write(".grok/auth.json", #"{"https://accounts.x.ai": {"email": "me@example.com"}}"#)
        let billingLine = Self.billing.replacingOccurrences(of: "\n", with: " ")
        // 가짜 grok agent stdio (ACP, 예전 버전): 로그 줄을 섞어 보내고, 슬래시가 이스케이프되지 않은 메서드 이름에만 응답한다.
        // 새 이름(`_x.ai/billing`)은 모르므로 Method not found → 프로바이더가 예전 이름으로 다시 묻는다.
        try home.writeScript("grok", """
        [ "$1" = "agent" ] && [ "$2" = "stdio" ] || exit 9
        echo "grok agent ready"
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/^{"id":\\([0-9]*\\),.*/\\1/p')
          case "$line" in
            *'"jsonrpc":"2.0"'*) ;;
            *) printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32600,"message":"missing jsonrpc"}}\\n' "$id"; continue ;;
          esac
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":1}}\\n' "$id" ;;
            *'"method":"x.ai/billing"'*)
              printf '{"jsonrpc":"2.0","method":"session/update","params":{}}\\n'
              printf '{"jsonrpc":"2.0","id":%s,"result":%s}\\n' "$id" '\(billingLine)' ;;
            *) printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"Method not found"}}\\n' "$id" ;;
          esac
        done
        """)
        let snapshot = try await GrokSubscriptionProvider(context: makeContext(home: home)).fetchUsage()
        #expect(snapshot.windows.first?.usedPercent == 25)
        #expect(snapshot.source == "grok agent")
    }

    @Test func providerPrefersUnderscoredExtensionMethod() async throws {
        let home = try TemporaryDirectory()
        try home.write(".grok/auth.json", "{}")
        let billingLine = Self.unifiedBilling.replacingOccurrences(of: "\n", with: " ")
        // 가짜 grok 1.0.46: ACP 확장 메서드는 밑줄로 시작해야 하고, 밑줄 없는 이름은 Method not found.
        try home.writeScript("grok", """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/^{"id":\\([0-9]*\\),.*/\\1/p')
          case "$line" in
            *'"method":"initialize"'*) printf '{"jsonrpc":"2.0","id":%s,"result":{"protocolVersion":1}}\\n' "$id" ;;
            *'"method":"_x.ai/billing"'*) printf '{"jsonrpc":"2.0","id":%s,"result":%s}\\n' "$id" '\(billingLine)' ;;
            *) printf '{"jsonrpc":"2.0","id":%s,"error":{"code":-32601,"message":"Method not found"}}\\n' "$id" ;;
          esac
        done
        """)
        let snapshot = try await GrokSubscriptionProvider(context: makeContext(home: home)).fetchUsage()
        #expect(snapshot.windows.first?.usedPercent == 37.5)
        #expect(snapshot.plan == "SuperGrok")
    }

    @Test func missingCLIOrLogin() async throws {
        let home = try TemporaryDirectory()
        let provider = GrokSubscriptionProvider(context: makeContext(home: home))
        await #expect(throws: ProviderError.setupRequired(GrokSubscriptionProvider.installHint)) {
            try await provider.fetchUsage()
        }
        try home.writeScript("grok", "exit 0")
        await #expect(throws: ProviderError.setupRequired(GrokSubscriptionProvider.loginHint)) {
            try await provider.fetchUsage()
        }
    }
}

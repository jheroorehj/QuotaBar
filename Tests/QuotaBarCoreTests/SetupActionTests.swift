import Foundation
import Testing
@testable import QuotaBarCore

@Suite("SetupAction")
struct SetupActionTests {
    private func action(_ service: ServiceID, _ error: ProviderError) -> SetupAction? {
        SetupAction.resolve(for: .subscription(service), error: error)
    }

    @Test func loginCommands() {
        #expect(action(.claude, .setupRequired(ClaudeSubscriptionProvider.loginHint))?.command == "claude")
        #expect(action(.claude, .authExpired(ClaudeSubscriptionProvider.expiredHint))?.command == "claude")
        #expect(action(.codex, .setupRequired(CodexSubscriptionProvider.loginHint))?.command == "codex login")
        #expect(action(.grok, .authExpired(GrokSubscriptionProvider.loginHint)) == SetupAction(kind: .login, command: "grok login"))
    }

    @Test func missingCLIOffersInstall() throws {
        let grok = try #require(action(.grok, .setupRequired(GrokSubscriptionProvider.installHint)))
        #expect(grok.kind == .install)
        #expect(grok.title == "설치하고 로그인")
        #expect(grok.command.contains("https://x.ai/cli/install.sh"))
        #expect(grok.command.contains("login"))

        let agy = try #require(action(.gemini, .setupRequired(GeminiSubscriptionProvider.antigravityHint)))
        #expect(agy.kind == .install)
        #expect(agy.command == "brew install --cask antigravity-cli && agy")
    }

    /// 처음 쓰는 사람은 CLI 자체가 없을 수 있다. 없으면 명령 대신 설치 안내를 보여줄 수 있어야 한다.
    @Test func loginActionsNameTheToolTheyNeed() throws {
        let claude = try #require(action(.claude, .setupRequired(ClaudeSubscriptionProvider.loginHint)))
        #expect(claude.prerequisite?.tool == "claude")
        #expect(claude.prerequisite?.installURL.hasPrefix("https://") == true)
        #expect(action(.codex, .setupRequired(CodexSubscriptionProvider.loginHint))?.prerequisite?.tool == "codex")
        #expect(action(.gemini, .setupRequired(GeminiSubscriptionProvider.geminiCLIHint))?.prerequisite?.tool == "gemini")
        #expect(action(.gemini, .setupRequired(GeminiSubscriptionProvider.antigravityHint))?.prerequisite?.tool == "brew")
        // 스스로 내려받아 설치하는 명령은 미리 필요한 도구가 없다.
        #expect(action(.grok, .setupRequired(GrokSubscriptionProvider.installHint))?.prerequisite == nil)
    }

    @Test func geminiPaths() {
        #expect(action(.gemini, .setupRequired("Antigravity 로그인이 필요합니다. 터미널에서 `agy` 를 실행해 로그인하세요."))?.command == "agy")
        #expect(action(.gemini, .setupRequired(GeminiSubscriptionProvider.consumerShutdownHint))?.command == "agy")
        #expect(action(.gemini, .setupRequired(GeminiSubscriptionProvider.geminiCLIHint))?.command == "gemini")
        let update = action(.gemini, .setupRequired("agy 1.1.0 은 사용량 조회를 지원하지 않습니다. agy 를 1.1.11 이상으로 업데이트하세요."))
        #expect(update?.kind == .update)
        #expect(update?.command == "brew upgrade --cask antigravity-cli")
    }

    @Test func noActionWhenNothingToDo() {
        #expect(action(.grok, .network("offline")) == nil)
        #expect(action(.codex, .timeout(20)) == nil)
        #expect(SetupAction.resolve(for: .api(.claude), error: .setupRequired("키 없음")) == nil)
    }
}

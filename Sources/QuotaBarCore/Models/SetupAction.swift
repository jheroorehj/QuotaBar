import Foundation

/// 사용자의 조치가 필요한 오류(설치·로그인)를 해결하는 터미널 명령.
/// 앱은 이 명령을 터미널에서 실행하는 버튼을 보여준다. 자격증명 파일은 CLI 가 직접 쓴다.
public struct SetupAction: Equatable, Sendable {
    public enum Kind: Sendable {
        case login
        /// CLI 를 내려받아 설치한다. 실행 전에 사용자 확인을 받는다.
        case install
        case update
    }

    /// 명령을 실행하려면 먼저 깔려 있어야 하는 도구와, 없을 때 안내할 설치 페이지.
    public struct Prerequisite: Equatable, Sendable {
        public let tool: String
        public let installURL: String
    }

    public let kind: Kind
    /// 버튼 문구.
    public let title: String
    /// 사용자의 로그인 셸에서 실행할 명령.
    public let command: String
    /// 이 도구가 없으면 명령을 실행하지 않고 설치 안내를 보여준다. (처음 쓰는 사람은 CLI 자체가 없을 수 있다)
    public let prerequisite: Prerequisite?

    public init(kind: Kind, command: String, prerequisite: Prerequisite? = nil) {
        self.kind = kind
        self.command = command
        self.prerequisite = prerequisite
        self.title = switch kind {
        case .login: "로그인"
        case .install: "설치하고 로그인"
        case .update: "업데이트"
        }
    }

    /// 오류를 해결할 명령. 조치가 필요 없는 오류(네트워크, 형식 등)와 API 프로바이더는 nil.
    public static func resolve(for id: ProviderID, error: ProviderError) -> SetupAction? {
        guard id.kind == .subscription else { return nil }
        let message: String
        switch error {
        case let .setupRequired(text), let .authExpired(text): message = text
        default: return nil
        }
        switch id.service {
        case .claude:
            return SetupAction(kind: .login, command: "claude", prerequisite: .claude)
        case .codex:
            return SetupAction(kind: .login, command: "codex login", prerequisite: .codex)
        case .gemini:
            if message == GeminiSubscriptionProvider.antigravityHint {
                return SetupAction(kind: .install, command: "brew install --cask antigravity-cli && agy", prerequisite: .homebrew)
            }
            if message.contains("업데이트하세요") {
                return SetupAction(kind: .update, command: "brew upgrade --cask antigravity-cli", prerequisite: .homebrew)
            }
            // 개인 계정 종료 안내는 Gemini CLI 를 언급하지만 해결책은 Antigravity 로그인이다.
            if message != GeminiSubscriptionProvider.consumerShutdownHint,
               message.contains("`gemini`") || message.contains("Gemini CLI") {
                return SetupAction(kind: .login, command: "gemini", prerequisite: .geminiCLI)
            }
            return SetupAction(kind: .login, command: "agy")
        case .grok:
            if message == GrokSubscriptionProvider.installHint {
                // 설치 직후에는 현재 셸의 PATH 에 grok 이 없을 수 있어 기본 설치 위치도 시도한다.
                return SetupAction(
                    kind: .install,
                    command: "curl -fsSL https://x.ai/cli/install.sh | bash && { command -v grok >/dev/null && grok login || \"$HOME/.grok/bin/grok\" login; }"
                )
            }
            return SetupAction(kind: .login, command: "grok login")
        }
    }
}

extension SetupAction.Prerequisite {
    static let claude = Self(tool: "claude", installURL: "https://claude.com/claude-code")
    static let codex = Self(tool: "codex", installURL: "https://github.com/openai/codex")
    static let geminiCLI = Self(tool: "gemini", installURL: "https://github.com/google-gemini/gemini-cli")
    static let homebrew = Self(tool: "brew", installURL: "https://brew.sh")
}

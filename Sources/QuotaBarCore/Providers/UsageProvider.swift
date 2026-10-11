import Foundation

/// 사용량을 가져오는 프로바이더. 서비스(Claude, Codex …) × 종류(구독/API) 마다 하나씩 만든다.
///
/// 새 프로바이더(예: API 사용량)를 추가하려면:
/// 1. 이 프로토콜을 구현하고 `fetchUsage()` 에서 `UsageSnapshot` 을 돌려준다.
/// 2. `ProviderRegistry.makeProviders` 에 등록한다.
public protocol UsageProvider: Sendable {
    var id: ProviderID { get }
    /// 이 시간 안에 끝나지 않으면 실패로 처리한다.
    var timeout: TimeInterval { get }
    func fetchUsage() async throws -> UsageSnapshot
}

extension UsageProvider {
    public var displayName: String { id.displayName }
}

/// 프로바이더들이 공유하는 의존성.
public struct ProviderContext: Sendable {
    public var config: QuotaBarConfig
    public var http: any HTTPClient
    public var locator: ExecutableLocator
    public var homeDirectory: URL
    /// macOS 키체인을 읽을지 여부. 테스트에서는 끈다.
    public var useSystemKeychain: Bool
    public var now: @Sendable () -> Date

    public init(
        config: QuotaBarConfig,
        http: any HTTPClient = URLSessionHTTPClient(),
        locator: ExecutableLocator,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        useSystemKeychain: Bool = true,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.http = http
        self.locator = locator
        self.homeDirectory = homeDirectory
        self.useSystemKeychain = useSystemKeychain
        self.now = now
    }

    /// 자식 프로세스(CLI)에 넘길 환경 변수. PATH 를 보강하고 `.env` 의 API 키는 넘기지 않는다.
    public var childEnvironment: [String: String] {
        locator.environment(base: config.childProcessEnvironment)
    }

    /// 실행 파일을 찾지 못하면 설치 안내와 함께 실패한다.
    func requireExecutable(_ name: String, setupHint: String) throws -> String {
        guard let path = locator.locate(name) else {
            throw ProviderError.setupRequired(setupHint)
        }
        return path
    }

    func readFile(_ url: URL) -> Data? {
        try? Data(contentsOf: url)
    }
}

/// 설정에 따라 사용할 프로바이더 목록을 만든다.
public enum ProviderRegistry {
    public static func makeProviders(context: ProviderContext) -> [any UsageProvider] {
        var providers: [any UsageProvider] = []
        let config = context.config

        // 구독(정액제) 사용량
        if config.isEnabled(.claude) { providers.append(ClaudeSubscriptionProvider(context: context)) }
        if config.isEnabled(.codex) { providers.append(CodexSubscriptionProvider(context: context)) }
        if config.isEnabled(.gemini) { providers.append(GeminiSubscriptionProvider(context: context)) }
        if config.isEnabled(.grok) { providers.append(GrokSubscriptionProvider(context: context)) }

        // API(종량제) 사용량
        providers += makeAPIProviders(context: context)
        return providers
    }

    /// API 사용량 프로바이더.
    ///
    /// `.env` 의 키는 `QuotaBarConfig.apiCredentials` 로 이미 읽히고 있다.
    /// 구현을 추가할 때는 키가 있는 서비스에 대해서만 프로바이더를 만들어 여기서 반환하면
    /// UI(카드), 일괄 새로고침, 10분 자동 갱신에 그대로 합류한다.
    ///   - Claude API  : Anthropic Admin API (`ANTHROPIC_ADMIN_API_KEY`)
    ///   - OpenAI API  : OpenAI Admin API (`OPENAI_ADMIN_API_KEY`)
    ///   - xAI API     : xAI Management API (`XAI_MANAGEMENT_API_KEY`, `XAI_TEAM_ID`)
    static func makeAPIProviders(context: ProviderContext) -> [any UsageProvider] {
        []
    }
}

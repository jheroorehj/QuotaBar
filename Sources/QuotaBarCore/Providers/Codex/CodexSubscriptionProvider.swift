import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Codex(ChatGPT Plus/Pro 등) 구독 사용 한도.
///
/// 1순위: `~/.codex/auth.json` 토큰으로 `GET https://chatgpt.com/backend-api/wham/usage` (비공식 API)
/// 2순위: 토큰이 거부되면 `codex app-server` 를 띄워 `account/rateLimits/read` 호출.
///        토큰 갱신은 Codex CLI 가 직접 처리하므로 auth.json 을 건드리지 않는다.
public struct CodexSubscriptionProvider: UsageProvider {
    static let loginHint = "Codex 로그인 정보를 찾을 수 없습니다. 터미널에서 `codex login` 으로 ChatGPT 계정에 로그인하세요."
    static let expiredHint = "Codex 로그인이 만료되었습니다. 터미널에서 `codex` 를 한 번 실행하거나 `codex login` 으로 다시 로그인하세요."
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    public let id = ProviderID.subscription(.codex)
    public let timeout: TimeInterval = 45
    private let context: ProviderContext

    public init(context: ProviderContext) {
        self.context = context
    }

    var codexHome: URL {
        if let custom = context.config.path(QuotaBarConfig.Key.codexHome) {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return context.homeDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let authURL = codexHome.appendingPathComponent("auth.json")
        guard let data = context.readFile(authURL) else {
            throw ProviderError.setupRequired(Self.loginHint)
        }
        let auth = try CodexAuth.parse(data)

        do {
            return try await fetchFromWeb(auth: auth)
        } catch let error as ProviderError {
            switch error {
            case .authExpired, .invalidResponse:
                // 토큰 만료나 응답 형식 변경 시 Codex CLI 경로로 재시도한다.
                guard context.locator.locate("codex") != nil else { throw error }
                return try await fetchFromAppServer()
            default:
                throw error
            }
        }
    }

    private func fetchFromWeb(auth: CodexAuth) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("QuotaBar", forHTTPHeaderField: "User-Agent")
        if let accountID = auth.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await context.http.send(request)
        try HTTPStatus.check(response, data: data, authMessage: Self.expiredHint)
        return try Self.makeWebSnapshot(data: data, fetchedAt: context.now())
    }

    static func makeWebSnapshot(data: Data, fetchedAt: Date) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(CodexWebUsageResponse.self, from: data)
        let windows = response.windows()
        guard !windows.isEmpty else { throw ProviderError.invalidResponse("rate_limit 정보가 없습니다.") }
        return UsageSnapshot(
            providerID: .subscription(.codex),
            plan: CodexWindowMapping.planName(response.planType),
            windows: windows,
            source: "ChatGPT API",
            fetchedAt: fetchedAt
        )
    }

    private func fetchFromAppServer() async throws -> UsageSnapshot {
        let codex = try context.requireExecutable(
            "codex",
            setupHint: "Codex CLI 를 찾을 수 없습니다. 설치 후 `codex login` 하세요. (경로가 특이하면 .env 의 CODEX_CLI_PATH)"
        )
        let client = JSONRPCStdioClient(
            executable: codex,
            arguments: ["-s", "read-only", "-a", "never", "app-server"],
            environment: context.childEnvironment,
            currentDirectory: FileManager.default.temporaryDirectory,
            includeVersionField: false
        )
        try client.start()
        defer { client.shutdown() }

        do {
            _ = try await client.request(
                "initialize",
                params: ["clientInfo": ["name": "quotabar", "version": "0.1.0"]],
                timeout: 15
            )
            try client.notify("initialized")
            let result = try await client.request("account/rateLimits/read", timeout: 15)
            return try Self.makeRPCSnapshot(result: result, fetchedAt: context.now())
        } catch let error as JSONRPCError {
            if case let .remote(_, message) = error, message.localizedCaseInsensitiveContains("auth") {
                throw ProviderError.authExpired(Self.expiredHint)
            }
            throw ProviderError.commandFailed("codex app-server: \(error.localizedDescription)")
        }
    }

    static func makeRPCSnapshot(result: JSONValue, fetchedAt: Date) throws -> UsageSnapshot {
        let decoded: CodexRPCRateLimitsResult
        do {
            decoded = try result.decode(as: CodexRPCRateLimitsResult.self)
        } catch {
            throw ProviderError.invalidResponse("account/rateLimits/read: \(error)")
        }
        let windows = decoded.windows()
        guard !windows.isEmpty else { throw ProviderError.invalidResponse("rateLimits 정보가 없습니다.") }
        return UsageSnapshot(
            providerID: .subscription(.codex),
            plan: CodexWindowMapping.planName(decoded.rateLimits.planType),
            windows: windows,
            source: "codex app-server",
            fetchedAt: fetchedAt
        )
    }
}

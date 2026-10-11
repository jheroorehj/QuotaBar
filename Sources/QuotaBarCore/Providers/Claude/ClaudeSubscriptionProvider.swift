import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Claude 구독(Pro/Max) 사용 한도.
///
/// Claude Code 로그인 토큰으로 `GET https://api.anthropic.com/api/oauth/usage` 를 호출한다. (비공식 API)
/// 토큰을 직접 갱신하면 Claude Code 의 refresh token 이 무효화될 수 있으므로,
/// 만료 시에는 `claude auth status` 를 실행해 Claude Code 가 스스로 갱신하도록 맡긴다.
public struct ClaudeSubscriptionProvider: UsageProvider {
    static let loginHint = "Claude Code 로그인 정보를 찾을 수 없습니다. 터미널에서 `claude` 를 실행해 로그인하세요."
    static let expiredHint = "Claude 로그인이 만료되었습니다. 터미널에서 `claude` 를 한 번 실행하면 갱신됩니다."
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let betaHeader = "oauth-2025-04-20"
    static let userAgent = "claude-code/2.1.0"

    public let id = ProviderID.subscription(.claude)
    public let timeout: TimeInterval = 30
    private let context: ProviderContext

    public init(context: ProviderContext) {
        self.context = context
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let reader = ClaudeCredentialsReader(context: context)
        var credentials = try await reader.read()
        var refreshedByCLI = false

        if credentials.isExpired(now: context.now()) {
            credentials = try await refreshThroughCLI(reader: reader)
            refreshedByCLI = true
        }

        do {
            return try await requestUsage(credentials: credentials)
        } catch ProviderError.authExpired where !refreshedByCLI {
            // 만료 시각 전이라도 서버가 거부하면 한 번만 CLI 갱신 후 재시도한다.
            credentials = try await refreshThroughCLI(reader: reader)
            return try await requestUsage(credentials: credentials)
        }
    }

    private func requestUsage(credentials: ClaudeOAuthCredentials) async throws -> UsageSnapshot {
        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await context.http.send(request)
        try HTTPStatus.check(response, data: data, authMessage: Self.expiredHint)
        return try Self.makeSnapshot(data: data, credentials: credentials, fetchedAt: context.now())
    }

    static func makeSnapshot(data: Data, credentials: ClaudeOAuthCredentials, fetchedAt: Date) throws -> UsageSnapshot {
        let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data)
        let windows = response.windows()
        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("사용량 항목이 없습니다.")
        }
        return UsageSnapshot(
            providerID: .subscription(.claude),
            plan: credentials.planName,
            windows: windows,
            source: "OAuth API",
            fetchedAt: fetchedAt
        )
    }

    /// Claude Code CLI 를 짧게 실행해 토큰 갱신을 맡긴 뒤 다시 읽는다.
    private func refreshThroughCLI(reader: ClaudeCredentialsReader) async throws -> ClaudeOAuthCredentials {
        guard let claude = context.locator.locate("claude") else {
            throw ProviderError.authExpired(Self.expiredHint)
        }
        _ = try? await ProcessRunner.run(
            executable: claude,
            arguments: ["auth", "status", "--json"],
            environment: context.childEnvironment,
            currentDirectory: FileManager.default.temporaryDirectory,
            timeout: 20
        )
        let credentials = try await reader.read()
        if credentials.isExpired(now: context.now()) {
            throw ProviderError.authExpired(Self.expiredHint)
        }
        return credentials
    }
}

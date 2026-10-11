import Foundation

/// Grok 구독(SuperGrok) 사용량.
///
/// `grok agent stdio`(ACP, 줄 단위 JSON-RPC 2.0)를 띄워 billing 확장 메서드를 호출한다.
/// ACP 확장 메서드는 밑줄로 시작한다(`_x.ai/billing`, grok 1.0.46 에서 확인). 밑줄 없는 이름은 예전 버전용 대체 경로.
/// `grok login`(SuperGrok 계정) 이 되어 있어야 한다.
public struct GrokSubscriptionProvider: UsageProvider {
    static let installHint = "Grok CLI(`grok`)를 찾을 수 없습니다. 설치 후 `grok login` 으로 SuperGrok 계정에 로그인하세요."
    static let loginHint = "Grok 로그인이 필요합니다. 터미널에서 `grok login` 을 실행하세요."

    public let id = ProviderID.subscription(.grok)
    public let timeout: TimeInterval = 40
    private let context: ProviderContext

    public init(context: ProviderContext) {
        self.context = context
    }

    var grokHome: URL {
        if let custom = context.config.path(QuotaBarConfig.Key.grokHome) {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return context.homeDirectory.appendingPathComponent(".grok", isDirectory: true)
    }

    public func fetchUsage() async throws -> UsageSnapshot {
        let grok = try context.requireExecutable("grok", setupHint: Self.installHint)
        guard context.readFile(grokHome.appendingPathComponent("auth.json")) != nil else {
            throw ProviderError.setupRequired(Self.loginHint)
        }

        let client = JSONRPCStdioClient(
            executable: grok,
            arguments: ["agent", "stdio"],
            environment: context.childEnvironment,
            currentDirectory: FileManager.default.temporaryDirectory,
            includeVersionField: true
        )
        try client.start()
        defer { client.shutdown() }

        let result: JSONValue
        do {
            _ = try await client.request(
                "initialize",
                params: [
                    "protocolVersion": "1",
                    "clientCapabilities": [
                        "fs": ["readTextFile": false, "writeTextFile": false],
                        "terminal": false,
                    ],
                ],
                timeout: 15
            )
            do {
                result = try await client.request("_x.ai/billing", timeout: 15)
            } catch let JSONRPCError.remote(_, message) where message.lowercased().contains("method not found") {
                result = try await client.request("x.ai/billing", timeout: 15)
            }
        } catch let error as JSONRPCError {
            if case let .remote(_, message) = error {
                let lower = message.lowercased()
                if lower.contains("auth") || lower.contains("login") {
                    throw ProviderError.authExpired(Self.loginHint)
                }
            }
            throw ProviderError.commandFailed("grok agent: \(error.localizedDescription)")
        }
        return try Self.makeSnapshot(result: result, fetchedAt: context.now())
    }

    static func makeSnapshot(result: JSONValue, fetchedAt: Date) throws -> UsageSnapshot {
        let billing: GrokBillingResponse
        do {
            billing = try result.decode(as: GrokBillingResponse.self)
        } catch {
            throw ProviderError.invalidResponse("x.ai/billing: \(error)")
        }
        return UsageSnapshot(
            providerID: .subscription(.grok),
            plan: billing.subscriptionTier,
            windows: [try billing.window()],
            source: "grok agent",
            fetchedAt: fetchedAt
        )
    }
}

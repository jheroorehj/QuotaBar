import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Claude Code 가 저장한 OAuth 로그인 정보 (`claudeAiOauth`).
public struct ClaudeOAuthCredentials: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?
    public let subscriptionType: String?
    public let rateLimitTier: String?

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        // 만료 직전 토큰은 요청 도중 만료될 수 있으므로 1분 여유를 둔다.
        return expiresAt.addingTimeInterval(-60) <= now
    }

    /// `{"claudeAiOauth": {"accessToken": …, "expiresAt": <ms>, "subscriptionType": "max", …}}`
    public static func parse(_ data: Data) throws -> ClaudeOAuthCredentials {
        struct Root: Decodable {
            let claudeAiOauth: OAuth?
        }
        struct OAuth: Decodable {
            let accessToken: String?
            let expiresAt: Double?
            let subscriptionType: String?
            let rateLimitTier: String?
        }
        let root = try JSONDecoder().decode(Root.self, from: data)
        guard let oauth = root.claudeAiOauth,
              let token = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else {
            throw ProviderError.setupRequired(ClaudeSubscriptionProvider.loginHint)
        }
        return ClaudeOAuthCredentials(
            accessToken: token,
            expiresAt: DateParsing.unix(oauth.expiresAt),
            subscriptionType: oauth.subscriptionType,
            rateLimitTier: oauth.rateLimitTier
        )
    }

    /// 플랜 표시 이름. rateLimitTier 에 5x/20x 정보가 들어 있다.
    public var planName: String? {
        let tier = rateLimitTier?.lowercased() ?? ""
        if tier.contains("20x") { return "Max 20x" }
        if tier.contains("5x") { return "Max 5x" }
        guard let type = subscriptionType?.trimmingCharacters(in: .whitespaces).lowercased(), !type.isEmpty else {
            return nil
        }
        switch type {
        case "max": return "Max"
        case "pro": return "Pro"
        case "team": return "Team"
        case "enterprise": return "Enterprise"
        case "free": return "Free"
        default: return type.capitalized
        }
    }
}

/// Claude Code 로그인 정보를 읽는다.
///
/// - macOS: 키체인 항목 `Claude Code-credentials` 를 `/usr/bin/security` 로 읽는다.
///   (Claude Code 가 같은 도구로 저장하므로 대개 추가 권한 요청 없이 읽힌다)
/// - 공통: `~/.claude/.credentials.json` (또는 `$CLAUDE_CONFIG_DIR/.credentials.json`)
struct ClaudeCredentialsReader: Sendable {
    let configDirectory: URL
    let customConfigDirectory: Bool
    let useKeychain: Bool

    init(context: ProviderContext) {
        useKeychain = context.useSystemKeychain
        if let custom = context.config.path(QuotaBarConfig.Key.claudeConfigDir) {
            configDirectory = URL(fileURLWithPath: custom, isDirectory: true)
            customConfigDirectory = true
        } else {
            configDirectory = context.homeDirectory.appendingPathComponent(".claude", isDirectory: true)
            customConfigDirectory = false
        }
    }

    func read() async throws -> ClaudeOAuthCredentials {
        #if os(macOS)
        for service in keychainServiceNames() where useKeychain {
            if let data = await readKeychain(service: service),
               let credentials = try? ClaudeOAuthCredentials.parse(data)
            {
                return credentials
            }
        }
        #endif
        let file = configDirectory.appendingPathComponent(".credentials.json")
        guard let data = try? Data(contentsOf: file) else {
            throw ProviderError.setupRequired(ClaudeSubscriptionProvider.loginHint)
        }
        return try ClaudeOAuthCredentials.parse(data)
    }

    /// `CLAUDE_CONFIG_DIR` 를 쓰면 Claude Code 는 경로 해시(sha256 앞 8자리)를 붙인 키체인 이름을 쓴다.
    func keychainServiceNames() -> [String] {
        var names: [String] = []
        if customConfigDirectory, let suffix = Self.sha256Prefix(configDirectory.path) {
            names.append("Claude Code-credentials-\(suffix)")
        }
        names.append("Claude Code-credentials")
        return names
    }

    static func sha256Prefix(_ text: String) -> String? {
        #if canImport(CryptoKit)
        let digest = SHA256.hash(data: Data(text.utf8))
        return String(digest.map { String(format: "%02x", $0) }.joined().prefix(8))
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private func readKeychain(service: String) async -> Data? {
        guard let result = try? await ProcessRunner.run(
            executable: "/usr/bin/security",
            arguments: ["find-generic-password", "-s", service, "-w"],
            timeout: 10
        ), result.exitCode == 0 else { return nil }
        let text = result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : Data(text.utf8)
    }
    #endif
}

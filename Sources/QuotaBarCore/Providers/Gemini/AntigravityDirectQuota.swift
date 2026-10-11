import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Antigravity CLI 가 macOS 키체인(서비스 `gemini`, 계정 `antigravity`)에 저장한 로그인 토큰.
///
/// Go 의 keyring 패키지 형식이라 `go-keyring-base64:` 뒤에 base64 로 감싼 JSON 이 온다.
/// ```json
/// {"auth_method": "consumer",
///  "token": {"access_token": "…", "refresh_token": "…", "expiry": "2026-10-08T15:34:12.165885+09:00"}}
/// ```
/// 읽기만 한다. 만료된 토큰의 갱신은 `agy` 에 맡긴다 (CLI 를 한 번 실행하면 키체인의 토큰이 새로 써진다).
struct AntigravityStoredToken: Equatable, Sendable {
    static let keychainService = "gemini"
    static let keychainAccount = "antigravity"
    private static let goKeyringPrefix = "go-keyring-base64:"

    let accessToken: String
    let expiresAt: Date?

    func isUsable(now: Date) -> Bool {
        guard !accessToken.isEmpty else { return false }
        guard let expiresAt else { return true }
        // 요청 도중 만료되지 않도록 1분 여유를 둔다.
        return expiresAt.addingTimeInterval(-60) > now
    }

    static func parse(_ keychainText: String) -> AntigravityStoredToken? {
        struct Stored: Decodable {
            struct Token: Decodable {
                let accessToken: String?
                let expiry: String?

                enum CodingKeys: String, CodingKey {
                    case accessToken = "access_token"
                    case expiry
                }
            }
            let token: Token?
        }
        var text = keychainText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix(goKeyringPrefix) {
            text = String(text.dropFirst(goKeyringPrefix.count))
        }
        guard let payload = Data(base64Encoded: text),
              let stored = try? JSONDecoder().decode(Stored.self, from: payload),
              let accessToken = stored.token?.accessToken, !accessToken.isEmpty
        else { return nil }
        return AntigravityStoredToken(accessToken: accessToken, expiresAt: DateParsing.iso8601(stored.token?.expiry))
    }
}

/// Antigravity 가 쓰는 Cloud Code 사용량 API (비공식).
///
/// `agy -p /usage` 는 실행할 때마다 계정 점검을 하고, 그중 프로필 사진 받기가 실패하면 통째로 실패한다
/// (google-antigravity/antigravity-cli#621). 같은 숫자를 이 API 로 직접 받으면 그 점검을 거치지 않는다.
/// 응답은 `agy /usage` 의 `command.data` 와 같은 구조에 키만 camelCase 다.
enum AntigravityQuotaAPI {
    static let quotaSummaryURL = URL(string: "https://daily-cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary")!
    static let userAgent = "antigravity/hub/2.8.0 (aidev_client; os_type=darwin; arch=arm64; cl=963137146)"
    static let clientMetadata = "ideType=IDE_UNSPECIFIED,platform=PLATFORM_UNSPECIFIED,pluginType=GEMINI"

    static func request(_ url: URL, token: String, body: String = "{}") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(clientMetadata, forHTTPHeaderField: "Client-Metadata")
        request.httpBody = Data(body.utf8)
        return request
    }

    /// `"Google AI Pro"` → `"AI Pro"`. 다른 타일의 "Pro"·"Plus" 처럼 짧게 보여준다.
    static func shortPlanName(_ name: String?) -> String? {
        guard var name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        if name.hasPrefix("Google ") { name = String(name.dropFirst("Google ".count)) }
        return name
    }
}

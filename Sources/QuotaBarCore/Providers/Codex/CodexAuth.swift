import Foundation

/// Codex CLI 의 `auth.json` (ChatGPT 로그인).
///
/// ```json
/// {"OPENAI_API_KEY": null,
///  "tokens": {"id_token": "…", "access_token": "…", "refresh_token": "…", "account_id": "…"},
///  "last_refresh": "2026-10-08T00:00:00Z"}
/// ```
public struct CodexAuth: Equatable, Sendable {
    public let accessToken: String
    public let accountID: String?

    public static func parse(_ data: Data) throws -> CodexAuth {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("auth.json 형식이 올바르지 않습니다.")
        }
        guard let tokens = root["tokens"] as? [String: Any],
              let accessToken = Self.string(tokens, "access_token", "accessToken")
        else {
            throw ProviderError.setupRequired(CodexSubscriptionProvider.loginHint)
        }
        let accountID = Self.string(tokens, "account_id", "accountId")
            ?? Self.string(tokens, "id_token", "idToken").flatMap(Self.accountID(fromIDToken:))
        return CodexAuth(accessToken: accessToken, accountID: accountID)
    }

    /// id_token(JWT) 의 `https://api.openai.com/auth.chatgpt_account_id` 클레임.
    static func accountID(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if let auth = payload["https://api.openai.com/auth"] as? [String: Any],
           let id = auth["chatgpt_account_id"] as? String, !id.isEmpty
        {
            return id
        }
        return payload["chatgpt_account_id"] as? String
    }

    private static func string(_ dictionary: [String: Any], _ keys: String...) -> String? {
        for key in keys {
            if let value = (dictionary[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

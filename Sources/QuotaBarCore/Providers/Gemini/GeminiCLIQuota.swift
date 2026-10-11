import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Gemini CLI OAuth 로그인 정보 (`~/.gemini/oauth_creds.json`).
struct GeminiOAuthCredentials: Equatable, Sendable {
    let accessToken: String?
    let refreshToken: String?
    let expiresAt: Date?

    static func parse(_ data: Data) throws -> GeminiOAuthCredentials {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("oauth_creds.json 형식이 올바르지 않습니다.")
        }
        let expiry = (root["expiry_date"] as? Double) ?? (root["expiry_date"] as? Int).map(Double.init)
        return GeminiOAuthCredentials(
            accessToken: root["access_token"] as? String,
            refreshToken: root["refresh_token"] as? String,
            expiresAt: DateParsing.unix(expiry)
        )
    }

    func isUsable(now: Date) -> Bool {
        guard let accessToken, !accessToken.isEmpty else { return false }
        guard let expiresAt else { return true }
        return expiresAt.addingTimeInterval(-60) > now
    }
}

/// Gemini Code Assist 쿼터 API (비공식).
///
/// 1. `POST https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist` → 프로젝트 ID, 티어
/// 2. `POST https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota` → 모델별 남은 비율
enum GeminiCodeAssistAPI {
    static let loadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    static let retrieveQuotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    static let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!

    struct CodeAssistStatus: Equatable {
        let projectID: String?
        let plan: String?
    }

    /// 개인 계정 Gemini CLI 서비스 종료(2026-06) 응답인지 확인한다.
    static func isConsumerShutdown(_ body: String) -> Bool {
        let lower = body.lowercased()
        return lower.contains("no longer supported") || lower.contains("antigravity")
    }

    static func parseLoadCodeAssist(_ data: Data) throws -> CodeAssistStatus {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.invalidResponse("loadCodeAssist 응답이 올바르지 않습니다.")
        }
        var projectID: String?
        if let project = root["cloudaicompanionProject"] as? String {
            projectID = project
        } else if let project = root["cloudaicompanionProject"] as? [String: Any] {
            projectID = (project["id"] as? String) ?? (project["name"] as? String)
        }
        var plan: String?
        if let paid = root["paidTier"] as? [String: Any], let name = paid["name"] as? String, !name.isEmpty {
            plan = name
        } else if let tier = root["currentTier"] as? [String: Any], let tierID = tier["id"] as? String {
            switch tierID {
            case "standard-tier": plan = "Standard"
            case "free-tier": plan = "Free"
            case "legacy-tier": plan = "Legacy"
            default: plan = (tier["name"] as? String) ?? tierID
            }
        }
        return CodeAssistStatus(projectID: projectID, plan: plan)
    }

    /// `{"buckets": [{"remainingFraction": 0.93, "resetTime": "…", "modelId": "gemini-2.5-pro"}]}`
    static func parseQuota(_ data: Data) throws -> [UsageWindow] {
        struct Response: Decodable {
            struct Bucket: Decodable {
                let remainingFraction: Double?
                let resetTime: String?
                let modelId: String?
            }

            let buckets: [Bucket]?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        // 같은 모델의 여러 버킷 중 가장 적게 남은 것을 쓴다.
        var lowest: [String: (fraction: Double, reset: String?)] = [:]
        for bucket in response.buckets ?? [] {
            guard let model = bucket.modelId, let fraction = bucket.remainingFraction, fraction.isFinite else { continue }
            if let existing = lowest[model], existing.fraction <= fraction { continue }
            lowest[model] = (fraction, bucket.resetTime)
        }
        guard !lowest.isEmpty else { throw ProviderError.invalidResponse("쿼터 버킷이 없습니다.") }
        return lowest
            .sorted { modelOrder($0.key) < modelOrder($1.key) || (modelOrder($0.key) == modelOrder($1.key) && $0.key < $1.key) }
            .map { model, info in
                .fromRemainingFraction(
                    id: model,
                    label: "일간 · \(modelLabel(model))",
                    remainingFraction: info.fraction,
                    resetsAt: DateParsing.iso8601(info.reset)
                )
            }
    }

    static func modelLabel(_ modelID: String) -> String {
        // "gemini-2.5-pro" → "2.5 Pro"
        var text = modelID
        if text.hasPrefix("gemini-") { text.removeFirst("gemini-".count) }
        return text.split(separator: "-").map { part in
            part.first?.isLetter == true ? part.capitalized : String(part)
        }.joined(separator: " ")
    }

    private static func modelOrder(_ modelID: String) -> Int {
        let lower = modelID.lowercased()
        if lower.contains("pro") { return 0 }
        if lower.contains("flash") && !lower.contains("lite") { return 1 }
        return 2
    }

    /// 설치된 Gemini CLI 의 OAuth 클라이언트 ID/시크릿을 찾는다. (공개된 설치형 앱 클라이언트 값)
    static func extractClientCredentials(fromScript contents: String) -> (id: String, secret: String)? {
        func firstMatch(_ pattern: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            let range = NSRange(contents.startIndex..., in: contents)
            guard let match = regex.firstMatch(in: contents, range: range),
                  match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: contents)
            else { return nil }
            return String(contents[valueRange])
        }
        guard let id = firstMatch(#"OAUTH_CLIENT_ID\s*=\s*['"]([\w\-\.]+)['"]"#),
              let secret = firstMatch(#"OAUTH_CLIENT_SECRET\s*=\s*['"]([\w\-]+)['"]"#)
        else { return nil }
        return (id, secret)
    }
}

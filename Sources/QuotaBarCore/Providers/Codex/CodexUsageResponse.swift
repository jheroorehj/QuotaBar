import Foundation

/// `GET https://chatgpt.com/backend-api/wham/usage` 응답.
///
/// ```json
/// {"plan_type": "plus",
///  "rate_limit": {"primary_window": {"used_percent": 12, "limit_window_seconds": 18000, "reset_at": 1791450000},
///                 "secondary_window": {…}},
///  "additional_rate_limits": [{"limit_name": "…", "rate_limit": {…}}]}
/// ```
struct CodexWebUsageResponse: Decodable {
    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            primaryWindow = try? container.decodeIfPresent(Window.self, forKey: .primaryWindow)
            secondaryWindow = try? container.decodeIfPresent(Window.self, forKey: .secondaryWindow)
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let limitWindowSeconds: Double?
        let resetAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case limitWindowSeconds = "limit_window_seconds"
            case resetAt = "reset_at"
        }
    }

    struct AdditionalRateLimit: Decodable {
        let limitName: String?
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case rateLimit = "rate_limit"
        }
    }

    let planType: String?
    let rateLimit: RateLimit?
    let additionalRateLimits: [AdditionalRateLimit]?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case additionalRateLimits = "additional_rate_limits"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        planType = try? container.decodeIfPresent(String.self, forKey: .planType)
        rateLimit = try? container.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        additionalRateLimits = try? container.decodeIfPresent([AdditionalRateLimit].self, forKey: .additionalRateLimits)
    }

    func windows() -> [UsageWindow] {
        var result: [UsageWindow] = []
        result += Self.windows(from: rateLimit, idPrefix: "", labelSuffix: nil)
        for extra in additionalRateLimits ?? [] {
            let name = extra.limitName ?? "추가 한도"
            result += Self.windows(from: extra.rateLimit, idPrefix: "\(name.lowercased()).", labelSuffix: name)
        }
        return result
    }

    private static func windows(from rateLimit: RateLimit?, idPrefix: String, labelSuffix: String?) -> [UsageWindow] {
        guard let rateLimit else { return [] }
        return [rateLimit.primaryWindow, rateLimit.secondaryWindow].compactMap { $0 }.map { window in
            let minutes = window.limitWindowSeconds.map { Int($0 / 60) }
            return CodexWindowMapping.window(
                idPrefix: idPrefix,
                minutes: minutes,
                usedPercent: window.usedPercent,
                resetsAt: DateParsing.unix(window.resetAt),
                labelSuffix: labelSuffix
            )
        }
    }
}

/// `codex app-server` 의 `account/rateLimits/read` 결과.
///
/// ```json
/// {"rateLimits": {"primary": {"usedPercent": 12.0, "windowDurationMins": 300, "resetsAt": 1791450000},
///                 "secondary": {…}, "planType": "plus"}}
/// ```
struct CodexRPCRateLimitsResult: Decodable {
    struct Snapshot: Decodable {
        let primary: Window?
        let secondary: Window?
        let planType: String?
    }

    struct Window: Decodable {
        let usedPercent: Double
        let windowDurationMins: Int?
        let resetsAt: Double?
    }

    let rateLimits: Snapshot

    func windows() -> [UsageWindow] {
        [rateLimits.primary, rateLimits.secondary].compactMap { $0 }.map { window in
            CodexWindowMapping.window(
                idPrefix: "",
                minutes: window.windowDurationMins,
                usedPercent: window.usedPercent,
                resetsAt: DateParsing.unix(window.resetsAt),
                labelSuffix: nil
            )
        }
    }
}

enum CodexWindowMapping {
    static func window(idPrefix: String, minutes: Int?, usedPercent: Double, resetsAt: Date?, labelSuffix: String?) -> UsageWindow {
        let label = UsageFormatting.windowLabel(minutes: minutes)
        let id: String
        switch minutes {
        case 300: id = "session"
        case 10080: id = "weekly"
        default: id = "window.\(minutes ?? 0)"
        }
        return UsageWindow(
            id: idPrefix + id,
            label: labelSuffix.map { "\(label) · \($0)" } ?? label,
            usedPercent: usedPercent,
            resetsAt: resetsAt
        )
    }

    static func planName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces).lowercased(), !raw.isEmpty else { return nil }
        switch raw {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu", "education": return "Edu"
        case "free": return "Free"
        case "go": return "Go"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

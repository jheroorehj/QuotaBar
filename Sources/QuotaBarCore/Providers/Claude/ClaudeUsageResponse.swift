import Foundation

/// `GET https://api.anthropic.com/api/oauth/usage` 응답.
///
/// 두 가지 형태를 모두 지원한다.
/// - 이전 형태: `five_hour`, `seven_day`, `seven_day_opus`, `seven_day_sonnet` = `{utilization, resets_at}`
/// - 새 형태: `limits: [{kind, group, percent, resets_at, scope: {model: {display_name}}, is_active}]`
struct ClaudeUsageResponse: Decodable {
    struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }

    struct Limit: Decodable {
        struct Scope: Decodable {
            struct Model: Decodable {
                let id: String?
                let displayName: String?

                enum CodingKeys: String, CodingKey {
                    case id
                    case displayName = "display_name"
                }
            }

            let model: Model?
        }

        let kind: String?
        let group: String?
        let percent: Double?
        let resetsAt: String?
        let scope: Scope?
        let isActive: Bool?

        enum CodingKeys: String, CodingKey {
            case kind, group, percent, scope
            case resetsAt = "resets_at"
            case isActive = "is_active"
        }
    }

    struct ExtraUsage: Decodable {
        let isEnabled: Bool?
        let monthlyLimit: Double?
        let usedCredits: Double?
        let utilization: Double?

        enum CodingKeys: String, CodingKey {
            case isEnabled = "is_enabled"
            case monthlyLimit = "monthly_limit"
            case usedCredits = "used_credits"
            case utilization
        }
    }

    let fiveHour: Window?
    let sevenDay: Window?
    let sevenDayOpus: Window?
    let sevenDaySonnet: Window?
    let limits: [Limit]?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case limits
        case extraUsage = "extra_usage"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 필드 하나의 형식이 바뀌어도 전체가 실패하지 않도록 개별적으로 관대하게 읽는다.
        fiveHour = try? container.decodeIfPresent(Window.self, forKey: .fiveHour)
        sevenDay = try? container.decodeIfPresent(Window.self, forKey: .sevenDay)
        sevenDayOpus = try? container.decodeIfPresent(Window.self, forKey: .sevenDayOpus)
        sevenDaySonnet = try? container.decodeIfPresent(Window.self, forKey: .sevenDaySonnet)
        limits = try? container.decodeIfPresent([Limit].self, forKey: .limits)
        extraUsage = try? container.decodeIfPresent(ExtraUsage.self, forKey: .extraUsage)
    }

    /// 화면에 보여줄 한도 목록.
    func windows() -> [UsageWindow] {
        var result: [UsageWindow] = []
        func add(_ window: UsageWindow) {
            if !result.contains(where: { $0.id == window.id }) { result.append(window) }
        }

        // 1) 새 형태(limits)를 우선한다.
        for limit in limits ?? [] where limit.isActive != false {
            guard let percent = limit.percent, percent.isFinite else { continue }
            let kind = (limit.kind ?? "").lowercased()
            let group = (limit.group ?? "").lowercased()
            let resetsAt = DateParsing.iso8601(limit.resetsAt)
            let modelName = limit.scope?.model?.displayName ?? limit.scope?.model?.id

            if kind.contains("session") || group == "session" || kind.contains("five_hour") {
                add(UsageWindow(id: "session", label: "5시간", usedPercent: percent, resetsAt: resetsAt))
            } else if kind == "weekly_scoped" || (group == "weekly" && modelName != nil) {
                let name = modelName ?? "모델"
                add(UsageWindow(
                    id: "weekly.\(name.lowercased())",
                    label: "주간 · \(name)",
                    usedPercent: percent,
                    resetsAt: resetsAt
                ))
            } else if kind.contains("weekly") || group == "weekly" {
                add(UsageWindow(id: "weekly", label: "주간", usedPercent: percent, resetsAt: resetsAt))
            } else if !kind.isEmpty {
                add(UsageWindow(id: kind, label: kind, usedPercent: percent, resetsAt: resetsAt))
            }
        }

        // 2) 이전 형태. limits 에 같은 한도가 없을 때만 채운다.
        let hasScopedLimits = result.contains { $0.id.hasPrefix("weekly.") }
        if let window = fiveHour, let utilization = window.utilization {
            add(UsageWindow(id: "session", label: "5시간", usedPercent: utilization, resetsAt: DateParsing.iso8601(window.resetsAt)))
        }
        if let window = sevenDay, let utilization = window.utilization {
            add(UsageWindow(id: "weekly", label: "주간", usedPercent: utilization, resetsAt: DateParsing.iso8601(window.resetsAt)))
        }
        if !hasScopedLimits {
            if let window = sevenDayOpus, let utilization = window.utilization {
                add(UsageWindow(id: "weekly.opus", label: "주간 · Opus", usedPercent: utilization, resetsAt: DateParsing.iso8601(window.resetsAt)))
            }
            if let window = sevenDaySonnet, let utilization = window.utilization {
                add(UsageWindow(id: "weekly.sonnet", label: "주간 · Sonnet", usedPercent: utilization, resetsAt: DateParsing.iso8601(window.resetsAt)))
            }
        }

        // 3) 추가 사용량(월 한도)이 켜져 있으면 함께 보여준다.
        if let extra = extraUsage, extra.isEnabled == true, let utilization = extra.utilization {
            var detail: String?
            if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                detail = String(format: "$%.2f / $%.2f", used / 100, limit / 100)
            }
            add(UsageWindow(id: "extra", label: "추가 사용량", usedPercent: utilization, resetsAt: nil, detail: detail))
        }
        return result
    }
}

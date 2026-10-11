import Foundation

/// `grok agent stdio` 의 billing 결과. 금액은 `{ "val": <센트> }` 형태. 두 가지 형식이 있다.
///
/// 새 형식 (grok 1.0.46, `_x.ai/billing`): 사용률을 퍼센트로 직접 준다.
/// ```json
/// {"config": {"creditUsagePercent": 37.5,
///             "currentPeriod": {"type": "USAGE_PERIOD_TYPE_WEEKLY", "start": "…", "end": "…"},
///             "onDemandCap": {"val": 0}, "onDemandUsed": {"val": 0}},
///  "subscription_tier": "SuperGrok"}
/// ```
///
/// 예전 형식 (`x.ai/billing`): 한도와 사용 금액을 준다.
/// ```json
/// {"billingCycle": {"billingPeriodStart": "2026-10-06T00:00:00Z", "billingPeriodEnd": "2026-10-13T00:00:00Z"},
///  "monthlyLimit": {"val": 5000},
///  "usage": {"includedUsed": {"val": 1250}, "onDemandUsed": {"val": 0}, "totalUsed": {"val": 1250}}}
/// ```
struct GrokBillingResponse: Decodable {
    struct Cents: Decodable {
        let val: Int?

        enum CodingKeys: String, CodingKey { case val }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // protobuf int64 는 JSON 에서 문자열로 올 수 있다.
            if let value = try? container.decode(Int.self, forKey: .val) {
                val = value
            } else if let value = try? container.decode(String.self, forKey: .val) {
                val = Int(value)
            } else if let value = try? container.decode(Double.self, forKey: .val) {
                val = Int(value)
            } else {
                val = nil
            }
        }
    }

    struct BillingCycle: Decodable {
        let billingPeriodStart: String?
        let billingPeriodEnd: String?
    }

    struct Usage: Decodable {
        let includedUsed: Cents?
        let onDemandUsed: Cents?
        let totalUsed: Cents?
    }

    struct Period: Decodable {
        let type: String?
        let start: String?
        let end: String?
    }

    struct Config: Decodable {
        let creditUsagePercent: Double?
        let currentPeriod: Period?
        let onDemandCap: Cents?
        let onDemandUsed: Cents?
        let billingPeriodStart: String?
        let billingPeriodEnd: String?
    }

    let billingCycle: BillingCycle?
    let monthlyLimit: Cents?
    let usage: Usage?
    let config: Config?
    let subscriptionTier: String?

    enum CodingKeys: String, CodingKey {
        case billingCycle, monthlyLimit, usage, config
        case subscriptionTier = "subscription_tier"
    }

    func window() throws -> UsageWindow {
        if let config, let percent = config.creditUsagePercent {
            return Self.unifiedWindow(config: config, percent: percent)
        }
        guard let limit = monthlyLimit?.val, limit > 0 else {
            throw ProviderError.invalidResponse("Grok 사용 한도(monthlyLimit)가 없습니다.")
        }
        guard let used = usage?.totalUsed?.val ?? usage?.includedUsed?.val else {
            throw ProviderError.invalidResponse("Grok 사용량(totalUsed)이 없습니다.")
        }
        let start = DateParsing.iso8601(billingCycle?.billingPeriodStart)
        let end = DateParsing.iso8601(billingCycle?.billingPeriodEnd)
        var minutes: Int?
        if let start, let end, end > start {
            minutes = Int(end.timeIntervalSince(start) / 60)
        }
        return UsageWindow(
            id: "billing",
            label: Self.periodLabel(minutes: minutes),
            usedPercent: Double(used) / Double(limit) * 100,
            resetsAt: end,
            detail: "\(UsageFormatting.dollars(cents: used)) / \(UsageFormatting.dollars(cents: limit))"
        )
    }

    private static func unifiedWindow(config: Config, percent: Double) -> UsageWindow {
        let start = DateParsing.iso8601(config.currentPeriod?.start ?? config.billingPeriodStart)
        let end = DateParsing.iso8601(config.currentPeriod?.end ?? config.billingPeriodEnd)
        let label: String
        switch config.currentPeriod?.type {
        case "USAGE_PERIOD_TYPE_WEEKLY": label = "주간"
        case "USAGE_PERIOD_TYPE_MONTHLY": label = "월간"
        default:
            var minutes: Int?
            if let start, let end, end > start {
                minutes = Int(end.timeIntervalSince(start) / 60)
            }
            label = periodLabel(minutes: minutes)
        }
        // 추가 과금(on-demand)을 켰을 때만 금액을 보여준다.
        var detail: String?
        if let cap = config.onDemandCap?.val, cap > 0 {
            detail = "추가 사용 \(UsageFormatting.dollars(cents: config.onDemandUsed?.val ?? 0)) / \(UsageFormatting.dollars(cents: cap))"
        }
        return UsageWindow(id: "billing", label: label, usedPercent: percent, resetsAt: end, detail: detail)
    }

    /// 청구 주기 길이로 주간/월간을 구분한다. (SuperGrok 은 주간 공용 한도)
    static func periodLabel(minutes: Int?) -> String {
        guard let minutes else { return "사용량" }
        if minutes <= 8 * 1440 { return "주간" }
        if minutes >= 27 * 1440 { return "월간" }
        return UsageFormatting.windowLabel(minutes: minutes)
    }
}

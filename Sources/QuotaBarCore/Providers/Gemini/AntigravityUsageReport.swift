import Foundation

/// `agy -p /usage --output-format json` 출력.
///
/// ```json
/// {"status": "SUCCESS",
///  "command": {"name": "usage",
///              "data": {"groups": [{"name": "Gemini Models",
///                                   "buckets": [{"id": "gemini-weekly", "name": "Weekly Limit Remaining",
///                                                "window": "weekly", "remaining_fraction": 0.86,
///                                                "reset_time": "2026-09-17T18:40:27Z"}]}]}}}
/// ```
struct AntigravityUsageReport: Decodable {
    struct Command: Decodable {
        let name: String?
        let data: Payload?
    }

    struct Payload: Decodable {
        let description: String?
        let groups: [Group]?
    }

    /// CLI 출력은 snake_case, 사용량 API(`retrieveUserQuotaSummary`)는 camelCase 라 둘 다 읽는다.
    struct Group: Decodable {
        let name: String?
        let displayName: String?
        let buckets: [Bucket]?

        enum CodingKeys: String, CodingKey {
            case name, buckets, displayName
            case displayNameSnake = "display_name"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
                ?? container.decodeIfPresent(String.self, forKey: .displayNameSnake)
            buckets = try container.decodeIfPresent([Bucket].self, forKey: .buckets)
        }
    }

    struct Bucket: Decodable {
        let id: String?
        let name: String?
        let window: String?
        let remainingFraction: Double?
        let resetTime: String?
        let disabled: Bool?

        enum CodingKeys: String, CodingKey {
            case id, name, window, disabled, bucketId, displayName, remainingFraction, resetTime
            case remainingFractionSnake = "remaining_fraction"
            case resetTimeSnake = "reset_time"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(String.self, forKey: .id)
                ?? container.decodeIfPresent(String.self, forKey: .bucketId)
            name = try container.decodeIfPresent(String.self, forKey: .name)
                ?? container.decodeIfPresent(String.self, forKey: .displayName)
            window = try container.decodeIfPresent(String.self, forKey: .window)
            remainingFraction = try container.decodeIfPresent(Double.self, forKey: .remainingFraction)
                ?? container.decodeIfPresent(Double.self, forKey: .remainingFractionSnake)
            resetTime = try container.decodeIfPresent(String.self, forKey: .resetTime)
                ?? container.decodeIfPresent(String.self, forKey: .resetTimeSnake)
            disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        }
    }

    let status: String?
    let command: Command?
    /// 실패했을 때의 사유. 예: `Eligibility check failed: … i/o timeout`
    let error: String?

    /// - Parameter includeThirdParty: Antigravity 안에서 쓰는 Claude·GPT 모델 한도도 포함할지 여부.
    ///   기본은 Gemini 모델 한도만 (다른 서비스처럼 5시간·주간 두 개).
    static func parse(_ data: Data, includeThirdParty: Bool = false) throws -> [UsageWindow] {
        let report: AntigravityUsageReport
        do {
            report = try JSONDecoder().decode(AntigravityUsageReport.self, from: Self.jsonPortion(of: data))
        } catch {
            throw ProviderError.invalidResponse("agy /usage 출력이 JSON 이 아닙니다.")
        }
        if report.status != "SUCCESS", let reason = report.error, !reason.isEmpty {
            // 형식 문제가 아니라 agy 쪽 실패(대개 일시적인 네트워크 오류)다.
            throw ProviderError.commandFailed("agy: \(ProviderError.shorten(reason, limit: 120))")
        }
        guard report.status == "SUCCESS", report.command?.name == "usage" else {
            throw ProviderError.invalidResponse("agy /usage 가 실패했습니다 (status: \(report.status ?? "없음")).")
        }

        let windows = Self.windows(from: report.command?.data?.groups ?? [], includeThirdParty: includeThirdParty)
        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("agy /usage 에 쿼터 정보가 없습니다.")
        }
        return windows
    }

    /// 사용량 API(`retrieveUserQuotaSummary`) 응답: `{"groups": [{"displayName": …, "buckets": [{"bucketId": …}]}]}`
    static func parseSummary(_ data: Data, includeThirdParty: Bool = false) throws -> [UsageWindow] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw ProviderError.invalidResponse("Antigravity 사용량 응답이 JSON 이 아닙니다.")
        }
        let windows = Self.windows(from: payload.groups ?? [], includeThirdParty: includeThirdParty)
        guard !windows.isEmpty else {
            throw ProviderError.invalidResponse("Antigravity 사용량 응답에 쿼터 정보가 없습니다.")
        }
        return windows
    }

    static func windows(from allGroups: [Group], includeThirdParty: Bool) -> [UsageWindow] {
        var groups = allGroups
        if !includeThirdParty {
            let geminiOnly = allGroups.filter { !isThirdParty($0) }
            // Gemini 그룹을 못 알아보면(이름이 바뀐 경우) 아무것도 안 보이는 것보다 전부 보여준다.
            if !geminiOnly.isEmpty { groups = geminiOnly }
        }
        var windows: [UsageWindow] = []
        for group in groups {
            let groupName = shortGroupName(group.displayName ?? group.name)
            for bucket in group.buckets ?? [] where bucket.disabled != true {
                guard let fraction = bucket.remainingFraction, fraction.isFinite else { continue }
                let windowName = windowLabel(bucket.window, fallback: bucket.name)
                let bucketID = bucket.id ?? "\(groupName).\(bucket.window ?? windowName)"
                windows.append(.fromRemainingFraction(
                    id: bucketID,
                    // 그룹이 하나뿐이면 다른 서비스처럼 기간만 쓴다.
                    label: groups.count > 1 ? "\(windowName) · \(groupName)" : windowName,
                    remainingFraction: fraction,
                    resetsAt: DateParsing.iso8601(bucket.resetTime)
                ))
            }
        }
        // 5시간 → 주간 순으로 정렬해 다른 서비스와 같은 순서로 보여준다.
        return windows.sorted { windowOrder($0.id) < windowOrder($1.id) }
    }

    /// 출력 앞뒤에 로그 줄이 섞여도 JSON 객체 부분만 잘라낸다.
    static func jsonPortion(of data: Data) -> Data {
        guard let start = data.firstIndex(of: UInt8(ascii: "{")),
              let end = data.lastIndex(of: UInt8(ascii: "}")),
              start < end
        else { return data }
        return data[start...end]
    }

    /// Antigravity 가 함께 주는 타사(Claude·GPT) 모델 그룹인지. 버킷 ID 는 `3p-` 로 시작한다.
    static func isThirdParty(_ group: Group) -> Bool {
        let lower = (group.displayName ?? group.name ?? "").lowercased()
        if lower.contains("claude") || lower.contains("gpt") { return true }
        let buckets = group.buckets ?? []
        return !buckets.isEmpty && buckets.allSatisfy { ($0.id ?? "").lowercased().hasPrefix("3p-") }
    }

    static func shortGroupName(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return "모델" }
        let lower = raw.lowercased()
        if lower.hasPrefix("gemini") { return "Gemini" }
        if lower.contains("claude") || lower.contains("gpt") { return "Claude·GPT" }
        return raw
    }

    static func windowLabel(_ window: String?, fallback: String?) -> String {
        switch window?.lowercased() {
        case "5h", "five_hour", "session": return "5시간"
        case "weekly", "week", "7d": return "주간"
        case "daily", "day", "24h": return "일간"
        default:
            let name = (fallback ?? "").lowercased()
            if name.contains("five hour") || name.contains("5 hour") { return "5시간" }
            if name.contains("weekly") { return "주간" }
            return fallback ?? "한도"
        }
    }

    private static func windowOrder(_ id: String) -> Int {
        let lower = id.lowercased()
        if lower.contains("5h") || lower.contains("five") { return 0 }
        if lower.contains("week") { return 1 }
        return 2
    }
}

import Foundation

/// 화면 표시용 문자열.
public enum UsageFormatting {
    public static let locale = Locale(identifier: "ko_KR")

    private static let formatters = DateFormatterCache(locale: locale)

    /// 58.4 → "58%"
    public static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    /// "14:32"
    public static func clockTime(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatters.string(from: date, format: "HH:mm", timeZone: timeZone)
    }

    /// 초기화 시각 설명.
    /// - 1분 미만: "곧 초기화"
    /// - 24시간 미만: "2시간 13분 후 초기화"
    /// - 그 이상: "10월 9일 (목) 09:00 초기화"
    public static func resetDescription(_ resetsAt: Date?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard let resetsAt else { return nil }
        let interval = resetsAt.timeIntervalSince(now)
        if interval < 60 { return "곧 초기화" }
        if interval < 24 * 3600 {
            return "\(duration(interval)) 후 초기화"
        }
        return "\(formatters.string(from: resetsAt, format: "M월 d일 (E) HH:mm", timeZone: timeZone)) 초기화"
    }

    /// 8000초 → "2시간 13분", 300초 → "5분"
    public static func duration(_ interval: TimeInterval) -> String {
        let totalMinutes = max(0, Int(interval / 60))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)분" }
        if minutes == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(minutes)분"
    }

    /// 한도 길이(분)를 이름으로: 300 → "5시간", 10080 → "주간"
    public static func windowLabel(minutes: Int?) -> String {
        guard let minutes, minutes > 0 else { return "한도" }
        switch minutes {
        case 10080: return "주간"
        case 1440: return "일간"
        case 40320...44640: return "월간"
        default:
            if minutes % 1440 == 0 { return "\(minutes / 1440)일" }
            if minutes % 60 == 0 { return "\(minutes / 60)시간" }
            return "\(minutes)분"
        }
    }

    /// 1250 센트 → "$12.50"
    public static func dollars(cents: Int) -> String {
        String(format: "$%.2f", Double(cents) / 100)
    }
}

/// `DateFormatter` 는 만드는 비용이 크다. 화면이 다시 그려질 때마다(게이지마다, 30초마다) 불리므로
/// 형식·시간대별로 하나씩 만들어 두고 다시 쓴다. 포매터는 스레드 간 공유가 안전하지 않아 잠금으로 감싼다.
private final class DateFormatterCache: @unchecked Sendable {
    private let locale: Locale
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    init(locale: Locale) {
        self.locale = locale
    }

    func string(from date: Date, format: String, timeZone: TimeZone) -> String {
        lock.lock()
        defer { lock.unlock() }
        let key = "\(format)|\(timeZone.identifier)"
        let formatter: DateFormatter
        if let cached = formatters[key] {
            formatter = cached
        } else {
            formatter = DateFormatter()
            formatter.locale = locale
            formatter.timeZone = timeZone
            formatter.dateFormat = format
            formatters[key] = formatter
        }
        return formatter.string(from: date)
    }
}

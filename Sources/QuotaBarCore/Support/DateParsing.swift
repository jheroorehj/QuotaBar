import Foundation

enum DateParsing {
    /// ISO 8601 날짜를 읽는다. 소수점 초(자릿수 무관)와 `Z`/`+09:00` 오프셋을 모두 허용한다.
    static func iso8601(_ raw: String?) -> Date? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        // "2026-10-08T07:00:00.512345+00:00" → "2026-10-08T07:00:00+00:00"
        if let dot = text.firstIndex(of: "."), let timeStart = text.firstIndex(of: "T"), dot > timeStart {
            var end = text.index(after: dot)
            while end < text.endIndex, text[end].isNumber { end = text.index(after: end) }
            text.removeSubrange(dot..<end)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        // 시간대가 없는 경우 UTC 로 본다.
        return formatter.date(from: text + "Z")
    }

    /// 유닉스 시각(초). 밀리초로 보이는 값은 초로 바꾼다.
    static func unix(_ value: Double?) -> Date? {
        guard let value, value > 0, value.isFinite else { return nil }
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

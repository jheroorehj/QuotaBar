/// 번들 아이콘이 없을 때 메뉴바에 쓰는 게이지 심볼. (표시는 StatusItemController 가 한다)
enum MenuBarLabel {
    static func symbolName(for percent: Double?) -> String {
        guard let percent else { return "gauge.with.dots.needle.0percent" }
        switch percent {
        case 90...: return "gauge.with.dots.needle.100percent"
        case 60..<90: return "gauge.with.dots.needle.67percent"
        case 25..<60: return "gauge.with.dots.needle.33percent"
        default: return "gauge.with.dots.needle.0percent"
        }
    }
}

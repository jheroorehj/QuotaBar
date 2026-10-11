import AppKit
import QuotaBarCore

/// 앱 번들(`Contents/Resources`)에 들어 있는 아이콘. 원본은 `Sources/Icons/`, 복사는 `scripts/build-app.sh` 가 한다.
/// 번들 없이 실행하면(`swift run QuotaBar`) nil 을 돌려주고, 호출하는 쪽이 SF Symbol·머리글자로 대체한다.
@MainActor
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    /// 메뉴바용 QuotaBar 아이콘. 템플릿 이미지라 메뉴바 색(밝음/어두움)을 따른다.
    /// 사용률이 바뀔 때마다 불리므로 한 번 만든 것을 다시 쓴다.
    static let menuBar: NSImage? = {
        guard let source = load("icons_QuotaBar.icns"), let image = source.copy() as? NSImage else { return nil }
        // 그림 둘레에 여백이 있어 메뉴바 높이에 가깝게 잡아야 다른 아이콘과 크기가 맞는다.
        image.size = NSSize(width: 22, height: 22)
        image.isTemplate = true
        return image
    }()

    /// 서비스 아이콘. 모두 단색(`[MONO]`) 파일이며, 그리는 쪽에서 글자색으로 칠한다.
    static func service(_ service: ServiceID) -> NSImage? {
        let file = switch service {
        case .claude: "[MONO]icons_claude.png"
        case .codex: "[MONO]icons_chatgpt.svg"
        case .gemini: "[MONO]icons_gemini.png"
        case .grok: "[MONO]icons_grok.svg"
        }
        return load(file)
    }

    private static func load(_ file: String) -> NSImage? {
        if let cached = cache[file] { return cached }
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(file),
              let image = NSImage(contentsOf: url) else { return nil }
        cache[file] = image
        return image
    }
}

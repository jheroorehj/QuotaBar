import AppKit
import QuotaBarCore
import SwiftUI

// Liquid Glass 적용 원칙
// - 창은 완전히 투명하다 (StatusItemController 의 패널). 배경을 칠하지 않는다.
// - 머리글·버튼·서비스 타일이 각각 유리 조각으로 바탕화면 위에 떠 있다 (제어 센터와 같은 구조).
// - 유리 위에 유리를 겹치지 않는다. 타일 안쪽은 글자·게이지만 둔다.
// - 인접한 유리 조각은 GlassEffectContainer 하나로 묶는다.
// - 유리는 `.clear` 를 쓴다. `.regular` 는 뒤를 거의 가릴 만큼 뿌옇다 (실제 화면 캡처로 비교함).
// - 앱이 활성 상태가 아니면 시스템이 유리를 불투명한 비활성 모양으로 그린다.
//   그래서 패널을 열 때 앱을 활성화한다 (StatusItemController).
// - 유리 뒤로 글자·그림이 그대로 비치므로 타일 안 글자는 한 단계 굵게 쓴다.
// - macOS 26 미만에서는 같은 구조를 유지한 채 창 뒤 블러(NSVisualEffectView)로 대체한다.
// - `#if compiler(>=6.2)`: Liquid Glass API 가 포함된 Xcode 26 SDK 에서만 컴파일한다.

/// DESIGN.md 의 spacing 토큰 (논리적 포인트). 사용자 정의 영역의 간격은 이 값만 쓴다.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}

enum Metrics {
    static let panelWidth: CGFloat = 340
    /// 유리의 그림자가 창 경계에서 잘리지 않도록 두는 투명 여백.
    static let windowMargin: CGFloat = 24
    static let tileRadius: CGFloat = 24
    static let iconSize: CGFloat = 16
    /// 머리글 캡슐과 높이를 맞춘 원형 버튼 크기.
    static let buttonSize: CGFloat = 44
    static let ringLineWidth: CGFloat = 5
    static let ringFillOpacity: Double = 0.55
    /// 한도 소진(100%) 게이지의 채움 농도. 가득 찬 빨간 고리가 너무 밝지 않도록 더 옅게 칠한다.
    static let ringExhaustedFillOpacity: Double = 0.32
    /// 유리 조각이 서로 붙기 시작하는 거리. 타일 간격(8)보다 조금 작게 두어 멈춰 있을 때는 떨어져 보인다.
    static let glassMergeDistance: CGFloat = 6
}

extension View {
    /// 유리 표면. macOS 26+ 는 Liquid Glass, 이전 버전은 창 뒤 블러.
    func glassSurface<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, interactive: interactive))
    }

    /// 글자·아이콘·게이지의 선 둘레에만 넓게 퍼지는 회색 번짐을 깔아, 유리의 투명도는 그대로 두고 글자를 또렷하게 한다.
    /// 설정 메뉴의 "글자 또렷하게"를 끄면 적용되지 않는다 (이전 모습으로 바로 복구).
    func textHalo(_ color: Color = .gray) -> some View {
        modifier(TextHalo(color: color))
    }

    /// 아이콘 버튼: 원형 유리 조각. 라벨이 `Metrics.buttonSize` 크기를 직접 잡는다.
    /// (`.buttonStyle(.glass)` 는 `.regular` 유리라 타일과 투명도가 달라 보여 쓰지 않는다)
    func glassIconButtonStyle() -> some View {
        buttonStyle(.plain).glassSurface(in: Circle(), interactive: true)
    }

    /// 아이콘 버튼의 라벨: 원 전체가 눌리도록 크기와 누름 영역을 잡는다.
    func glassIconButtonLabel() -> some View {
        frame(width: Metrics.buttonSize, height: Metrics.buttonSize).contentShape(Circle())
    }
}

enum Preferences {
    /// 글자 둘레 어둠(`textHalo`) 사용 여부. 기본은 켬.
    static let textHaloKey = "textHaloEnabled"
}

extension EnvironmentValues {
    /// 글자 둘레 번짐을 지금 그려도 되는지. 패널이 열리고 닫히는 동안에는 false.
    ///
    /// 번짐은 글자 묶음마다 흐린 사본 두 장을 그리는데, 타일이 움직이는 동안 매 프레임 다시 그리게 되어
    /// 화면이 끊긴다 (측정: 패널 열기 1.2초 동안 메인 스레드 멈춤 170~376ms → 끄면 약 67ms).
    var haloAllowed: Bool {
        get { self[HaloAllowedKey.self] }
        set { self[HaloAllowedKey.self] = newValue }
    }
}

// `@Entry` 매크로는 Xcode 없이 Command Line Tools 만 있는 환경에서 빌드되지 않아 키를 직접 선언한다.
private struct HaloAllowedKey: EnvironmentKey {
    static let defaultValue = true
}

private struct TextHalo: ViewModifier {
    /// 번짐 색. 글자·아이콘·게이지 고리 모두 회색 (검정보다 가벼워 사용자가 선택).
    let color: Color
    @AppStorage(Preferences.textHaloKey) private var isEnabled = true
    @Environment(\.haloAllowed) private var isAllowed

    func body(content: Content) -> some View {
        // 내용 모양대로 색을 채운 사본을 흐리게 만들어 뒤에 깐다. 글자·아이콘·게이지의 선 모양을 따라가는 번짐이 된다.
        // (`.shadow` 는 유리 위에서 밝게 떠 보이고, 사각 받침은 상자처럼 보여서 둘 다 쓰지 않는다)
        content.background {
            if isEnabled, isAllowed {
                ZStack {
                    // 넓게 퍼지는 층
                    color.mask { content }.blur(radius: 7).opacity(0.75)
                    // 선 바로 둘레를 잡아 주는 층
                    color.mask { content }.blur(radius: 2.5).opacity(0.6)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isAllowed)
    }
}

private struct GlassSurface<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool

    /// 유리에 얹는 색조. 검은 색유리로 보이도록 검정을 옅게 섞는다 (사용자 요청, 투명도는 20% 그대로).
    /// 글자는 패널을 어두운 모양(`darkAqua`)으로 고정해 흰색으로 쓴다 (StatusItemController).
    private static var legibilityTint: Color { Color.black.opacity(0.2) }

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(.clear.tint(Self.legibilityTint).interactive(interactive), in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content.background {
            BehindWindowBlur()
                .clipShape(shape)
                .overlay { shape.stroke(Color(nsColor: .separatorColor), lineWidth: 1) }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
        }
    }
}

/// 창 뒤의 내용을 흐리게 비추는 시스템 재질 (macOS 26 미만 대체용).
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// 인접한 유리 조각을 하나의 글래스 그룹으로 묶는다. 조각끼리 합쳐지지 않도록 결합 거리는 0.
struct GlassGroup<Content: View>: View {
    /// 이 거리 안으로 가까워진 유리 조각끼리는 물방울처럼 붙는다. 가만히 있을 때의 조각 간격보다 작아야 한다.
    var spacing: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// 사용률 단계. 화면에는 게이지 색으로만 나타낸다 (경고 기호는 보기 불편하다는 사용자 요청으로 뺌).
/// VoiceOver 에는 문구(`statusText`)로 함께 알린다.
enum UsageLevel {
    case normal, warning, critical
    /// 한도를 다 썼다. 빨강으로 두되 가득 찬 고리가 튀지 않도록 더 옅게 칠한다 (`ringFillOpacity`).
    case exhausted

    init(percent: Double) {
        switch percent {
        // 화면에 "100%" 로 반올림되어 보이는 값부터.
        case 99.5...: self = .exhausted
        case 90..<99.5: self = .critical
        case 75..<90: self = .warning
        default: self = .normal
        }
    }

    /// 시스템 색만 사용해 라이트/다크 설정을 따른다.
    var color: Color {
        switch self {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        case .exhausted: .red
        }
    }

    /// 게이지 고리 채움 농도.
    var ringFillOpacity: Double {
        self == .exhausted ? Metrics.ringExhaustedFillOpacity : Metrics.ringFillOpacity
    }

    var statusText: String? {
        switch self {
        case .normal: nil
        case .warning: "한도 근접"
        case .critical: "한도 임박"
        case .exhausted: "한도 소진"
        }
    }
}

extension ServiceID {
    /// 서비스 구분용 색 (번들 아이콘이 없을 때의 머리글자 배지에 사용).
    var tint: Color {
        switch self {
        case .claude: .orange
        case .codex: .teal
        case .gemini: .blue
        case .grok: .gray
        }
    }
}

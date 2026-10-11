import SwiftUI

/// 새로고침 진행 상황을 상자에 액체가 차오르는 모습으로 보여준다.
///
/// 수면은 물결치며 올라가고, 다 차면 잠깐 머문 뒤 사라진다.
/// "동작 줄이기"가 켜져 있으면 물결 없이 수위만 바뀐다.
struct LiquidFill: View {
    /// 새로고침 중인지.
    let isActive: Bool
    /// 진행률 0...1 (조회가 끝난 서비스의 비율).
    let progress: Double

    @State private var isVisible = false
    @State private var level: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: !isVisible || reduceMotion)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                // 뒤 물결은 느리고 옅게, 앞 물결은 조금 빠르게 — 겹쳐서 출렁이는 느낌을 낸다.
                Wave(level: level, phase: reduceMotion ? 0 : time * 1.6, amplitude: reduceMotion ? 0 : 2.5)
                    .fill(.white.opacity(0.14))
                Wave(level: level, phase: reduceMotion ? 0 : time * 2.4 + 1.7, amplitude: reduceMotion ? 0 : 1.8)
                    .fill(.white.opacity(0.18))
            }
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { sync(active: isActive) }
        .onChange(of: isActive) { _, active in sync(active: active) }
        .onChange(of: progress) { _, newValue in
            guard isActive else { return }
            withAnimation(.smooth(duration: 0.6)) { level = Self.displayLevel(newValue) }
        }
    }

    private func sync(active: Bool) {
        if active {
            // 바닥에서부터 다시 차오르게 한다.
            level = 0
            withAnimation(.smooth(duration: 0.25)) { isVisible = true }
            withAnimation(.smooth(duration: 0.6)) { level = Self.displayLevel(progress) }
        } else if isVisible {
            // 끝까지 채운 뒤 잠깐 보여 주고 사라진다.
            withAnimation(.smooth(duration: 0.35)) { level = 1.1 }
            withAnimation(.smooth(duration: 0.4).delay(0.5)) { isVisible = false }
        }
    }

    /// 막 시작했을 때도 액체가 조금 보이도록 바닥 수위를 둔다.
    private static func displayLevel(_ progress: Double) -> Double {
        0.12 + 0.88 * min(max(progress, 0), 1)
    }
}

/// 아래에서 `level` 만큼 차오른 물. 윗면이 사인 곡선으로 출렁인다.
private struct Wave: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let surface = rect.maxY - rect.height * level
        let wavelength = max(rect.width / 2.2, 1)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        var x = rect.minX
        while x <= rect.maxX {
            let y = surface + sin(Double(x) / wavelength * 2 * .pi + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 2
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

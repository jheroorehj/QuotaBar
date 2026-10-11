import AppKit
import QuartzCore

/// 화면 확인용: `QUOTABAR_FPS_LOG=1` 로 실행하면 패널이 열리는 1.2초 동안 메인 스레드가 얼마나 밀렸는지 출력한다.
/// (메인 스레드가 한 프레임(16.7ms)보다 오래 붙잡히면 그만큼 화면이 끊긴다)
@MainActor
enum HitchProbe {
    static var isRequested: Bool { ProcessInfo.processInfo.environment["QUOTABAR_FPS_LOG"] != nil }

    static func startIfRequested(_ label: String) {
        guard isRequested else { return }
        var stamps: [CFTimeInterval] = [CACurrentMediaTime()]
        let timer = Timer(timeInterval: 1.0 / 240.0, repeats: true) { _ in
            stamps.append(CACurrentMediaTime())
        }
        RunLoop.main.add(timer, forMode: .common)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            timer.invalidate()
            // 움직이는 동안(앞 0.7초)과 멈춘 뒤를 나눠서 본다. 끊겨 보이는 것은 앞쪽뿐이다.
            let start = stamps[0]
            var moving: [Double] = []
            var settled: [Double] = []
            for (later, earlier) in zip(stamps.dropFirst(), stamps) {
                let gap = (later - earlier) * 1000
                if earlier - start < 0.7 { moving.append(gap) } else { settled.append(gap) }
            }
            func summary(_ gaps: [Double]) -> String {
                let stalls = gaps.filter { $0 > 20 }
                return String(format: "worst=%.0fms stalls=%d total=%.0fms", gaps.max() ?? 0, stalls.count, stalls.reduce(0, +))
            }
            FileHandle.standardError.write(Data("HITCH \(label) moving[\(summary(moving))] settled[\(summary(settled))]\n".utf8))
        }
    }
}

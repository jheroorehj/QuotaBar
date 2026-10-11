// swift-tools-version: 6.0
import PackageDescription

// QuotaBarCore 와 quotabar-cli 는 Foundation 만 사용하므로 Linux 에서도 빌드/테스트할 수 있다.
// 메뉴바 앱(QuotaBar)은 SwiftUI/AppKit 이 필요하므로 macOS 에서만 패키지에 포함한다.
var products: [Product] = [
    .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
    // 앱 실행 파일(QuotaBar)과 이름이 대소문자만 다르면 macOS 기본 파일시스템에서 충돌하므로 -cli 를 붙인다.
    .executable(name: "quotabar-cli", targets: ["QuotaBarCLI"]),
]

var targets: [Target] = [
    .target(name: "QuotaBarCore"),
    .executableTarget(name: "QuotaBarCLI", dependencies: ["QuotaBarCore"]),
    .testTarget(name: "QuotaBarCoreTests", dependencies: ["QuotaBarCore"]),
]

#if os(macOS)
products.append(.executable(name: "QuotaBar", targets: ["QuotaBar"]))
targets.append(.executableTarget(
    name: "QuotaBar",
    dependencies: ["QuotaBarCore"],
    // UI 계층은 AppKit 콜백이 많아 Swift 5 모드로 둔다. 핵심 로직(QuotaBarCore)은 Swift 6 엄격 모드.
    swiftSettings: [.swiftLanguageMode(.v5)]
))
#endif

let package = Package(
    name: "QuotaBar",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)

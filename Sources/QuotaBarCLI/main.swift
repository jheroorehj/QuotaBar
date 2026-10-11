import Foundation
import QuotaBarCore

// quotabar-cli: 메뉴바 앱과 같은 코드로 사용량을 조회한다.
// 각 서비스 연동이 실제로 동작하는지 터미널에서 바로 확인할 때 쓴다.

let usage = """
사용법: quotabar-cli [명령] [옵션] [서비스...]

명령:
  (없음)        사용량 조회 (기본)
  config        현재 설정 확인 (API 키는 가려서 표시)
  init          설정 파일(~/.config/quotabar/.env)을 템플릿으로 만들기

옵션:
  --json        JSON 으로 출력
  -h, --help    도움말

서비스: claude, codex, gemini, grok (생략하면 켜진 서비스 전부)

예:
  quotabar-cli
  quotabar-cli claude codex
  quotabar-cli --json gemini
"""

var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("-h") || arguments.contains("--help") {
    print(usage)
    exit(0)
}

let asJSON = arguments.contains("--json")
arguments.removeAll { $0 == "--json" }
let command = arguments.first.flatMap { ["config", "init"].contains($0) ? $0 : nil }
if command != nil { arguments.removeFirst() }

let config = ConfigLoader.load()

switch command {
case "init":
    let url = ConfigLoader.defaultEnvFileURL()
    do {
        if try ConfigLoader.createDefaultEnvFileIfNeeded(at: url) {
            print("설정 파일을 만들었습니다: \(url.path)")
        } else {
            print("이미 설정 파일이 있습니다: \(url.path)")
        }
    } catch {
        FileHandle.standardError.write(Data("설정 파일을 만들 수 없습니다: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
    exit(0)

case "config":
    func mask(_ value: String?) -> String {
        guard let value else { return "(없음)" }
        return value.count <= 8 ? "설정됨" : "\(value.prefix(6))…\(value.suffix(2))"
    }
    let loginPATH = await ExecutableLocator.loginShellPATH(environment: config.processEnvironment)
    let locator = ExecutableLocator.make(config: config, loginShellPATH: loginPATH)
    print("설정 파일      : \(config.envFileURL?.path ?? "(없음 — 기본값 사용, `quotabar-cli init` 으로 생성)")")
    print("자동 갱신 주기 : \(Int(config.refreshInterval / 60))분")
    print("Gemini 소스    : \(config.geminiSource.rawValue)")
    print("")
    print("구독 서비스:")
    for service in ServiceID.allCases {
        print("  \(service.displayName.padding(toLength: 8, withPad: " ", startingAt: 0)) \(config.isEnabled(service) ? "켜짐" : "꺼짐")")
    }
    print("")
    print("CLI 실행 파일:")
    for name in ["claude", "codex", "agy", "gemini", "grok"] {
        print("  \(name.padding(toLength: 8, withPad: " ", startingAt: 0)) \(locator.locate(name) ?? "(찾을 수 없음)")")
    }
    print("")
    let api = config.apiCredentials
    print("API 키 (향후 API 사용량 표시용):")
    print("  ANTHROPIC_ADMIN_API_KEY  \(mask(api.anthropicAdminKey))")
    print("  OPENAI_ADMIN_API_KEY     \(mask(api.openAIAdminKey))")
    print("  XAI_MANAGEMENT_API_KEY   \(mask(api.xaiManagementKey))")
    print("  XAI_TEAM_ID              \(api.xaiTeamID ?? "(없음)")")
    exit(0)

default:
    break
}

// 사용량 조회
let requested = Set(arguments.map { $0.lowercased() })
let unknown = requested.subtracting(ServiceID.allCases.map(\.rawValue))
if !unknown.isEmpty {
    FileHandle.standardError.write(Data("알 수 없는 서비스: \(unknown.sorted().joined(separator: ", "))\n\n\(usage)\n".utf8))
    exit(2)
}

let loginPATH = await ExecutableLocator.loginShellPATH(environment: config.processEnvironment)
var providers = QuotaBarController.defaultProviders(config: config, loginShellPATH: loginPATH)
if !requested.isEmpty {
    providers = providers.filter { requested.contains($0.id.service.rawValue) }
}
if providers.isEmpty {
    FileHandle.standardError.write(Data("조회할 서비스가 없습니다. (.env 에서 꺼져 있는지 확인하세요)\n".utf8))
    exit(2)
}

let store = UsageStore(providers: providers)
await store.refreshAll(trigger: .manual)

if asJSON {
    struct Output: Encodable {
        let provider: String
        let snapshot: UsageSnapshot?
        let error: String?
    }
    let output = store.rows.map { row in
        Output(provider: row.id.description, snapshot: row.state.snapshot, error: row.state.error?.localizedDescription)
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(output)
    print(String(decoding: data, as: UTF8.self))
} else {
    func bar(_ percent: Double, width: Int = 16) -> String {
        let filled = Int((percent / 100 * Double(width)).rounded())
        return String(repeating: "█", count: filled) + String(repeating: "░", count: max(0, width - filled))
    }
    func pad(_ text: String, _ width: Int) -> String {
        let length = text.count + text.unicodeScalars.filter { $0.value >= 0x1100 }.count
        return text + String(repeating: " ", count: max(1, width - length))
    }
    for row in store.rows {
        var header = row.displayName
        if let plan = row.state.snapshot?.plan { header += " · \(plan)" }
        if let source = row.state.snapshot?.source { header += "  (\(source))" }
        print(header)
        for window in row.state.snapshot?.windows ?? [] {
            var line = "  \(pad(window.label, 22))\(bar(window.usedPercent)) \(pad(UsageFormatting.percent(window.usedPercent), 5))"
            if let reset = UsageFormatting.resetDescription(window.resetsAt) { line += "  \(reset)" }
            if let detail = window.detail { line += "  [\(detail)]" }
            print(line)
        }
        if let error = row.state.error {
            print("  ⚠︎ \(error.localizedDescription)")
        }
        print("")
    }
}

exit(store.rows.contains { $0.state.error != nil } ? 1 : 0)

import Foundation

/// CLI 실행 파일을 찾는다.
///
/// Finder/로그인 항목으로 실행된 macOS 앱은 셸의 PATH 를 물려받지 못하므로
/// (보통 `/usr/bin:/bin:/usr/sbin:/sbin` 만 있음) 로그인 셸의 PATH 와 흔한 설치 위치를 함께 뒤진다.
public struct ExecutableLocator: Sendable {
    public let searchDirectories: [String]
    private let overrides: [String: String]
    private let isExecutable: @Sendable (String) -> Bool

    public init(
        searchDirectories: [String],
        overrides: [String: String] = [:],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.searchDirectories = ExecutableLocator.deduplicated(searchDirectories)
        self.overrides = overrides
        self.isExecutable = isExecutable
    }

    /// 설정/환경 변수/로그인 셸 PATH 로부터 탐색 경로를 만든다.
    public static func make(config: QuotaBarConfig, loginShellPATH: String?, homeDirectory: String = NSHomeDirectory()) -> ExecutableLocator {
        var directories: [String] = []
        if let path = config.processEnvironment["PATH"] { directories += path.split(separator: ":").map(String.init) }
        if let loginShellPATH { directories += loginShellPATH.split(separator: ":").map(String.init) }
        directories += commonDirectories(homeDirectory: homeDirectory)

        var overrides: [String: String] = [:]
        let keys: [(String, String)] = [
            ("claude", QuotaBarConfig.Key.claudeCLIPath),
            ("codex", QuotaBarConfig.Key.codexCLIPath),
            ("agy", QuotaBarConfig.Key.antigravityCLIPath),
            ("gemini", QuotaBarConfig.Key.geminiCLIPath),
            ("grok", QuotaBarConfig.Key.grokCLIPath),
        ]
        for (name, key) in keys {
            if let path = config.path(key) { overrides[name] = path }
        }
        return ExecutableLocator(searchDirectories: directories, overrides: overrides)
    }

    /// 흔한 CLI 설치 위치.
    public static func commonDirectories(homeDirectory: String) -> [String] {
        var directories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/.claude/local",
            "\(homeDirectory)/.npm-global/bin",
            "\(homeDirectory)/.bun/bin",
            "\(homeDirectory)/.volta/bin",
            "\(homeDirectory)/.cargo/bin",
            "\(homeDirectory)/.grok/bin",
            "\(homeDirectory)/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        // nvm 으로 설치한 node 의 전역 패키지 (최신 버전 우선)
        let nvmRoot = "\(homeDirectory)/.nvm/versions/node"
        if let versions = try? FileManager.default.contentsOfDirectory(atPath: nvmRoot) {
            let sorted = versions.sorted { $0.compare($1, options: .numeric) == .orderedDescending }
            directories += sorted.map { "\(nvmRoot)/\($0)/bin" }
        }
        return directories
    }

    /// 실행 파일 경로. 설정에 지정된 경로가 있으면 그것만 사용한다.
    public func locate(_ name: String) -> String? {
        if let override = overrides[name] {
            return isExecutable(override) ? override : nil
        }
        for directory in searchDirectories {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// 자식 프로세스가 node 등 다른 도구를 찾을 수 있도록 PATH 를 채운 환경 변수.
    public func environment(base: [String: String]) -> [String: String] {
        var environment = base
        environment["PATH"] = searchDirectories.joined(separator: ":")
        return environment
    }

    static func deduplicated(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        return directories.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// 로그인 셸의 PATH 를 읽는다. 앱 시작 시 한 번만 호출한다.
    public static func loginShellPATH(environment: [String: String], timeout: TimeInterval = 3) async -> String? {
        let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return nil }
        let marker = "__QUOTABAR_PATH__"
        do {
            let result = try await ProcessRunner.run(
                executable: shell,
                arguments: ["-l", "-c", "printf '\(marker)%s\(marker)' \"$PATH\""],
                environment: environment,
                timeout: timeout
            )
            let output = result.stdoutString
            guard let start = output.range(of: marker),
                  let end = output.range(of: marker, range: start.upperBound..<output.endIndex)
            else { return nil }
            let path = String(output[start.upperBound..<end.lowerBound])
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }
}

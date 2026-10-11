import Foundation
import Testing
@testable import QuotaBarCore

@Suite("EnvFile")
struct EnvFileTests {
    @Test func parsesCommonForms() {
        let values = EnvFile.parse("""
        # 주석
        QUOTABAR_REFRESH_MINUTES=5
        export CODEX_HOME=~/.codex-work
        QUOTED="a b # not comment"
        SINGLE='raw \\n value'
        ESCAPED="line1\\nline2 \\"q\\""
        INLINE=value # 주석
        EMPTY=
          SPACED_KEY = spaced value
        1INVALID=x
        NO_EQUALS
        """)
        #expect(values["QUOTABAR_REFRESH_MINUTES"] == "5")
        #expect(values["CODEX_HOME"] == "~/.codex-work")
        #expect(values["QUOTED"] == "a b # not comment")
        #expect(values["SINGLE"] == "raw \\n value")
        #expect(values["ESCAPED"] == "line1\nline2 \"q\"")
        #expect(values["INLINE"] == "value")
        #expect(values["EMPTY"] == "")
        #expect(values["SPACED_KEY"] == "spaced value")
        #expect(values["1INVALID"] == nil)
        #expect(values["NO_EQUALS"] == nil)
    }

    @Test func templateParsesToDefaults() {
        let values = EnvFile.parse(EnvTemplate.contents)
        #expect(values["QUOTABAR_REFRESH_MINUTES"] == "10")
        #expect(values["QUOTABAR_GEMINI_SOURCE"] == "auto")
        // API 키 항목은 주석 처리되어 있어야 한다.
        #expect(values["ANTHROPIC_ADMIN_API_KEY"] == nil)
    }

    @Test func templateMatchesEnvExample() throws {
        let example = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".env.example")
        let contents = try String(contentsOf: example, encoding: .utf8)
        #expect(contents == EnvTemplate.contents + "\n", "scripts/sync-env-template.sh 를 실행하세요")
    }
}

@Suite("QuotaBarConfig")
struct QuotaBarConfigTests {
    @Test func defaults() {
        let config = QuotaBarConfig(values: [:])
        #expect(config.refreshInterval == 600)
        #expect(config.geminiSource == .auto)
        for service in ServiceID.allCases {
            #expect(config.isEnabled(service))
        }
        #expect(config.apiCredentials.configuredServices.isEmpty)
    }

    @Test func overrides() {
        let config = QuotaBarConfig(values: [
            "QUOTABAR_REFRESH_MINUTES": "15",
            "QUOTABAR_GROK_ENABLED": "false",
            "QUOTABAR_CODEX_ENABLED": "0",
            "QUOTABAR_GEMINI_SOURCE": "Antigravity",
            "ANTHROPIC_ADMIN_API_KEY": "sk-ant-admin-123",
            "XAI_MANAGEMENT_API_KEY": "  ",
        ])
        #expect(config.refreshInterval == 900)
        #expect(!config.isEnabled(.grok))
        #expect(!config.isEnabled(.codex))
        #expect(config.isEnabled(.claude))
        #expect(config.geminiSource == .antigravity)
        #expect(config.apiCredentials.configuredServices == [.claude])
    }

    @Test func refreshIntervalHasMinimum() {
        #expect(QuotaBarConfig(values: ["QUOTABAR_REFRESH_MINUTES": "0"]).refreshInterval == 60)
        #expect(QuotaBarConfig(values: ["QUOTABAR_REFRESH_MINUTES": "abc"]).refreshInterval == 600)
    }

    @Test func childEnvironmentExcludesAPIKeys() {
        let config = QuotaBarConfig(
            values: ["OPENAI_ADMIN_API_KEY": "secret", "CODEX_HOME": "~/work-codex"],
            processEnvironment: ["HOME": "/Users/me"]
        )
        let environment = config.childProcessEnvironment
        #expect(environment["OPENAI_ADMIN_API_KEY"] == nil)
        #expect(environment["CODEX_HOME"] == ("~/work-codex" as NSString).expandingTildeInPath)
        #expect(environment["HOME"] == "/Users/me")
    }

    @Test func loaderPrefersProcessEnvironment() throws {
        let home = try TemporaryDirectory()
        try home.write(".config/quotabar/.env", "QUOTABAR_REFRESH_MINUTES=3\nQUOTABAR_CLAUDE_ENABLED=false\n")
        let config = ConfigLoader.load(
            processEnvironment: ["QUOTABAR_REFRESH_MINUTES": "7"],
            homeDirectory: home.url,
            currentDirectory: nil
        )
        #expect(config.envFileURL?.lastPathComponent == ".env")
        #expect(config.refreshInterval == 420)
        #expect(!config.isEnabled(.claude))
    }

    @Test func explicitEnvFile() throws {
        let home = try TemporaryDirectory()
        let custom = try home.write("custom.env", "QUOTABAR_GEMINI_SOURCE=gemini-cli\n")
        let config = ConfigLoader.load(
            processEnvironment: ["QUOTABAR_ENV_FILE": custom.path],
            homeDirectory: home.url,
            currentDirectory: nil
        )
        #expect(config.geminiSource == .geminiCLI)
    }

    @Test func createsTemplateWithPrivatePermissions() throws {
        let home = try TemporaryDirectory()
        let url = ConfigLoader.defaultEnvFileURL(homeDirectory: home.url)
        #expect(try ConfigLoader.createDefaultEnvFileIfNeeded(at: url))
        #expect(try !ConfigLoader.createDefaultEnvFileIfNeeded(at: url))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
        #expect(try EnvFile.load(from: url)["QUOTABAR_REFRESH_MINUTES"] == "10")
    }
}

@Suite("ExecutableLocator")
struct ExecutableLocatorTests {
    @Test func findsInSearchDirectoriesAndRespectsOverride() throws {
        let home = try TemporaryDirectory()
        let codex = try home.writeScript("codex", "echo codex")
        let locator = ExecutableLocator(searchDirectories: ["/nonexistent", home.binDirectory])
        #expect(locator.locate("codex") == codex.path)
        #expect(locator.locate("grok") == nil)

        let overridden = ExecutableLocator(searchDirectories: [home.binDirectory], overrides: ["codex": "/nonexistent/codex"])
        #expect(overridden.locate("codex") == nil, "설정에 지정한 경로가 없으면 다른 곳을 찾지 않는다")
    }

    @Test func environmentUsesSearchPath() {
        let locator = ExecutableLocator(searchDirectories: ["/a", "/b", "/a", ""])
        #expect(locator.searchDirectories == ["/a", "/b"])
        #expect(locator.environment(base: ["X": "1"]) == ["X": "1", "PATH": "/a:/b"])
    }

    @Test func overridesComeFromConfig() {
        let config = QuotaBarConfig(values: ["GROK_CLI_PATH": "/opt/tools/grok"])
        let locator = ExecutableLocator.make(config: config, loginShellPATH: "/login/bin", homeDirectory: "/Users/me")
        #expect(locator.searchDirectories.contains("/login/bin"))
        #expect(locator.searchDirectories.contains("/opt/homebrew/bin"))
        #expect(locator.searchDirectories.contains("/Users/me/.local/bin"))
    }
}

@Suite("설정 파일 고쳐 쓰기")
struct EnvFileUpdateTests {
    static let file = """
    # QuotaBar 설정
    QUOTABAR_REFRESH_MINUTES=10

    # Gemini 타일에 표시할 구독 이름
    # QUOTABAR_GEMINI_PLAN=AI Pro
    QUOTABAR_GROK_ENABLED=true

    """

    @Test func replacesExistingLineAndKeepsTheRest() {
        let updated = EnvFile.updating(Self.file, key: "QUOTABAR_REFRESH_MINUTES", value: "30")
        #expect(updated == Self.file.replacingOccurrences(of: "QUOTABAR_REFRESH_MINUTES=10", with: "QUOTABAR_REFRESH_MINUTES=30"))
        #expect(EnvFile.parse(updated)["QUOTABAR_GROK_ENABLED"] == "true")
    }

    @Test func usesCommentedExampleLine() {
        let updated = EnvFile.updating(Self.file, key: "QUOTABAR_GEMINI_PLAN", value: "AI Ultra")
        #expect(updated.contains("# Gemini 타일에 표시할 구독 이름\nQUOTABAR_GEMINI_PLAN=\"AI Ultra\"\n"))
        #expect(EnvFile.parse(updated)["QUOTABAR_GEMINI_PLAN"] == "AI Ultra")
    }

    @Test func appendsUnknownKeyAndRemovesValue() {
        let appended = EnvFile.updating(Self.file, key: "QUOTABAR_CLAUDE_ENABLED", value: "false")
        #expect(appended.hasSuffix("QUOTABAR_CLAUDE_ENABLED=false\n"))
        let removed = EnvFile.updating(appended, key: "QUOTABAR_CLAUDE_ENABLED", value: nil)
        #expect(EnvFile.parse(removed)["QUOTABAR_CLAUDE_ENABLED"] == nil)
        #expect(removed.hasSuffix("# QUOTABAR_CLAUDE_ENABLED=false\n"))
    }

    @Test func collapsesDuplicateKeys() {
        let duplicated = "A=1\nB=2\nA=3\n"
        #expect(EnvFile.updating(duplicated, key: "A", value: "9") == "B=2\nA=9\n")
    }

    @Test func quotesValuesThatNeedIt() {
        #expect(EnvFile.formatValue("Pro") == "Pro")
        #expect(EnvFile.formatValue("AI Pro") == "\"AI Pro\"")
        let tricky = #"a "b" #c \d"#
        #expect(EnvFile.parse("K=" + EnvFile.formatValue(tricky))["K"] == tricky)
    }

    @Test func updateWritesFileAndKeepsItPrivate() throws {
        let home = try TemporaryDirectory()
        let url = home.url.appendingPathComponent("config/.env")
        try ConfigLoader.update(["QUOTABAR_GEMINI_PLAN": "Pro", "QUOTABAR_GROK_ENABLED": "false"], at: url)
        let values = try EnvFile.load(from: url)
        #expect(values["QUOTABAR_GEMINI_PLAN"] == "Pro")
        #expect(values["QUOTABAR_GROK_ENABLED"] == "false")
        #expect(values["QUOTABAR_GEMINI_SOURCE"] == "auto")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
}

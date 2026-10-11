import Foundation
import Testing
@testable import QuotaBarCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 심볼릭 링크를 모두 푼 실제 경로. (macOS 의 /var → /private/var 포함)
private func realPath(_ path: String) -> String {
    guard let resolved = realpath(path, nil) else { return path }
    defer { free(resolved) }
    return String(cString: resolved)
}

@Suite("ProcessRunner · JSON-RPC")
struct ProcessTests {
    @Test func capturesOutputAndExitCode() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2; exit 3"],
            timeout: 10
        )
        #expect(result.stdoutString == "out")
        #expect(result.stderrString == "err")
        #expect(result.exitCode == 3)
    }

    @Test func handlesLargeOutput() async throws {
        // 파이프 버퍼(64KB)보다 큰 출력에서도 멈추지 않아야 한다.
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "i=0; while [ $i -lt 20000 ]; do echo 0123456789; i=$((i+1)); done"],
            timeout: 30
        )
        #expect(result.stdout.count == 220_000)
    }

    @Test func timesOut() async throws {
        let start = Date()
        // `exec` 로 손자 프로세스를 남기지 않는다. Linux Foundation 은 동시에 실행 중인 다른 자식에게
        // 파이프가 상속될 수 있어, 오래 사는 손자가 있으면 병렬 테스트의 종료 감지가 늦어진다.
        await #expect(throws: ProcessRunnerError.timedOut(1)) {
            try await ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "exec sleep 30"], timeout: 1)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }

    @Test func launchFailure() async {
        await #expect(throws: ProcessRunnerError.self) {
            try await ProcessRunner.run(executable: "/nonexistent/tool", timeout: 5)
        }
    }

    @Test func passesEnvironmentAndDirectory() async throws {
        let directory = try TemporaryDirectory()
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "printf '%s|' \"$QB_TEST\"; pwd -P"],
            environment: ["QB_TEST": "hello", "PATH": "/usr/bin:/bin"],
            currentDirectory: directory.url,
            timeout: 10
        )
        let resolved = realPath(directory.url.path)
        #expect(result.stdoutString.trimmingCharacters(in: .whitespacesAndNewlines) == "hello|\(resolved)")
    }

    @Test func withTimeoutHelper() async throws {
        let value = try await withTimeout(seconds: 5) { 42 }
        #expect(value == 42)
        await #expect(throws: ProviderError.timeout(0.2)) {
            try await withTimeout(seconds: 0.2) {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
    }

    @Test func jsonValueEncodesIntegersAndSlashes() throws {
        let value: JSONValue = ["id": 1, "method": "x.ai/billing", "ratio": .number(0.5)]
        #expect(String(decoding: try value.encodedData(), as: UTF8.self) == #"{"id":1,"method":"x.ai/billing","ratio":0.5}"#)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"a":[true,null,"s",2.5]}"#.utf8))
        #expect(decoded == ["a": [true, .null, "s", .number(2.5)]])
    }

    @Test func jsonRPCRemoteErrorAndExit() async throws {
        let directory = try TemporaryDirectory()
        let server = try directory.writeScript("server", """
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -n 's/^{"id":\\([0-9]*\\),.*/\\1/p')
          case "$line" in
            *'"method":"quit"'*) echo "bye" >&2; exit 1 ;;
            *) printf '{"id":%s,"error":{"code":-32601,"message":"Method not found"}}\\n' "$id" ;;
          esac
        done
        """)
        let client = JSONRPCStdioClient(executable: server.path, arguments: [], includeVersionField: false)
        try client.start()
        defer { client.shutdown() }

        await #expect(throws: JSONRPCError.remote(method: "nope", message: "Method not found")) {
            try await client.request("nope", timeout: 5)
        }
        await #expect(throws: JSONRPCError.self) {
            try await client.request("quit", timeout: 5)
        }
    }

    @Test func jsonRPCTimeout() async throws {
        let directory = try TemporaryDirectory()
        let server = try directory.writeScript("silent", "while IFS= read -r line; do :; done")
        let client = JSONRPCStdioClient(executable: server.path, arguments: [], includeVersionField: true)
        try client.start()
        defer { client.shutdown() }
        await #expect(throws: JSONRPCError.timeout(method: "slow")) {
            try await client.request("slow", timeout: 0.5)
        }
    }
}

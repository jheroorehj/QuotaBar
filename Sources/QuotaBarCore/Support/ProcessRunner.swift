import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let stdout: Data
    public let stderr: Data

    public var stdoutString: String { String(decoding: stdout, as: UTF8.self) }
    public var stderrString: String { String(decoding: stderr, as: UTF8.self) }
}

public enum ProcessRunnerError: Error, LocalizedError, Equatable, Sendable {
    case launchFailed(String)
    case timedOut(TimeInterval)

    public var errorDescription: String? {
        switch self {
        case let .launchFailed(message): "실행할 수 없습니다: \(message)"
        case let .timedOut(seconds): "\(Int(seconds))초 안에 끝나지 않아 중단했습니다."
        }
    }
}

/// 외부 명령을 비동기로 실행한다.
///
/// - 표준 출력/오류는 버퍼가 가득 차 멈추지 않도록 이벤트 기반으로 계속 읽는다.
/// - 시간 초과나 Task 취소 시 SIGTERM, 2초 뒤에도 살아 있으면 SIGKILL 을 보낸다.
/// - 자식이 남긴 손자 프로세스가 파이프를 잡고 있어도 종료 후 잠시만 기다리고 결과를 돌려준다.
public enum ProcessRunner {
    public static func run(
        executable: String,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        timeout: TimeInterval
    ) async throws -> ProcessResult {
        ProcessSignals.ignoreSIGPIPE()
        let state = RunState()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        process.standardInput = FileHandle.nullDevice

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        state.attach(stdout: stdoutPipe.fileHandleForReading, stderr: stderrPipe.fileHandleForReading)

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ProcessResult, Error>) in
                state.setContinuation(continuation)
                process.terminationHandler = { finished in
                    let status = finished.terminationStatus
                    DispatchQueue.global(qos: .utility).async {
                        state.waitForOutput(grace: 1.0)
                        state.finish(exitCode: status)
                    }
                }
                do {
                    try process.run()
                } catch {
                    state.fail(ProcessRunnerError.launchFailed(error.localizedDescription))
                    return
                }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                    guard box.process.isRunning else { return }
                    state.markTimedOut(timeout)
                    box.terminate()
                    // 손자 프로세스가 남아 있으면 종료 알림이 늦게 올 수 있으므로(Linux) 오래 기다리지 않는다.
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                        state.fail(ProcessRunnerError.timedOut(timeout))
                    }
                }
            }
        } onCancel: {
            state.markCancelled()
            box.terminate()
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 3) {
                state.fail(CancellationError())
            }
        }
    }
}

/// Process 는 Sendable 이 아니므로 종료 신호를 보낼 때만 감싸서 넘긴다.
final class ProcessBox: @unchecked Sendable {
    let process: Process

    init(_ process: Process) {
        self.process = process
    }

    func terminate() {
        guard process.isRunning else { return }
        let pid = process.processIdentifier
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
            if self.process.isRunning { kill(pid, SIGKILL) }
        }
    }
}

private final class RunState: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data()
    private var stderr = Data()
    private var continuation: CheckedContinuation<ProcessResult, Error>?
    private var completed = false
    private var timedOutAfter: TimeInterval?
    private var cancelled = false
    private var handles: [FileHandle] = []
    private let outputGroup = DispatchGroup()

    func attach(stdout: FileHandle, stderr: FileHandle) {
        handles = [stdout, stderr]
        for (index, handle) in handles.enumerated() {
            outputGroup.enter()
            let isStdout = index == 0
            handle.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard let self else { return }
                if data.isEmpty {
                    handle.readabilityHandler = nil
                    self.outputGroup.leave()
                } else {
                    self.append(data, toStdout: isStdout)
                }
            }
        }
    }

    private func append(_ data: Data, toStdout: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if toStdout { stdout.append(data) } else { stderr.append(data) }
    }

    func setContinuation(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
    }

    func markTimedOut(_ seconds: TimeInterval) {
        lock.lock()
        timedOutAfter = seconds
        lock.unlock()
    }

    func markCancelled() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func waitForOutput(grace: TimeInterval) {
        if outputGroup.wait(timeout: .now() + grace) == .success { return }
        // EOF 가 오지 않았다. 다른 프로세스가 파이프를 물려받았을 수 있으므로
        // 이벤트 핸들러를 멈추고 파이프에 남은 데이터를 직접 비운다.
        for handle in handles {
            handle.readabilityHandler = nil
        }
        Thread.sleep(forTimeInterval: 0.05) // 실행 중이던 핸들러가 끝나기를 잠깐 기다린다.
        for (index, handle) in handles.enumerated() {
            drain(handle, toStdout: index == 0)
        }
    }

    private func drain(_ handle: FileHandle, toStdout: Bool) {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            append(Data(buffer[0..<count]), toStdout: toStdout)
        }
    }

    func finish(exitCode: Int32) {
        lock.lock()
        let timedOut = timedOutAfter
        let wasCancelled = cancelled
        let result = ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
        lock.unlock()

        if wasCancelled {
            resume(.failure(CancellationError()))
        } else if let timedOut {
            resume(.failure(ProcessRunnerError.timedOut(timedOut)))
        } else {
            resume(.success(result))
        }
    }

    func fail(_ error: Error) {
        resume(.failure(error))
    }

    private func resume(_ result: Result<ProcessResult, Error>) {
        lock.lock()
        guard !completed, let continuation else {
            lock.unlock()
            return
        }
        completed = true
        self.continuation = nil
        let handles = self.handles
        lock.unlock()

        for handle in handles {
            handle.readabilityHandler = nil
        }
        continuation.resume(with: result)
    }
}

enum ProcessSignals {
    private static let ignore: Void = {
        // 자식 프로세스가 먼저 종료된 뒤 stdin 에 쓰면 SIGPIPE 로 앱 전체가 종료되는 것을 막는다.
        signal(SIGPIPE, SIG_IGN)
    }()

    static func ignoreSIGPIPE() {
        _ = ignore
    }
}

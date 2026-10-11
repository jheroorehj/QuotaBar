import Foundation

public enum JSONRPCError: Error, LocalizedError, Equatable, Sendable {
    case notStarted
    case launchFailed(String)
    case processExited(String)
    case timeout(method: String)
    case remote(method: String, message: String)
    case missingResult(method: String)

    public var errorDescription: String? {
        switch self {
        case .notStarted: "JSON-RPC 프로세스가 시작되지 않았습니다."
        case let .launchFailed(message): "실행할 수 없습니다: \(message)"
        case let .processExited(detail): "프로세스가 응답 전에 종료되었습니다. \(detail)"
        case let .timeout(method): "`\(method)` 응답 시간 초과"
        case let .remote(method, message): "`\(method)` 오류: \(message)"
        case let .missingResult(method): "`\(method)` 응답에 result 가 없습니다."
        }
    }
}

/// 줄 단위 JSON-RPC 2.0 을 표준 입출력으로 주고받는 클라이언트.
///
/// `codex app-server` 와 `grok agent stdio` 가 이 방식을 쓴다.
/// Codex 는 `"jsonrpc"` 필드를 생략하고, Grok(ACP)은 `"jsonrpc": "2.0"` 을 포함한다.
public final class JSONRPCStdioClient: @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let environment: [String: String]?
    private let currentDirectory: URL?
    private let includeVersionField: Bool

    private let lock = NSLock()
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var buffer = Data()
    private var stderrTail = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var pendingMethods: [Int: String] = [:]
    private var exited = false

    public init(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: URL? = nil,
        includeVersionField: Bool
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
        self.currentDirectory = currentDirectory
        self.includeVersionField = includeVersionField
    }

    deinit {
        shutdown()
    }

    public func start() throws {
        ProcessSignals.ignoreSIGPIPE()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                self?.handleExit()
            } else {
                self?.handleStdout(data)
            }
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                self?.appendStderr(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            // stdout EOF 보다 먼저 올 수 있으므로 남은 출력이 처리될 시간을 조금 준다.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) {
                self.handleExit()
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw JSONRPCError.launchFailed(error.localizedDescription)
        }

        lock.lock()
        self.process = process
        self.stdinHandle = stdinPipe.fileHandleForWriting
        lock.unlock()
    }

    /// 요청을 보내고 `result` 를 기다린다.
    public func request(_ method: String, params: JSONValue = [:], timeout: TimeInterval) async throws -> JSONValue {
        let (id, isExited, hasStdin) = locked { () -> (Int, Bool, Bool) in
            let id = nextID
            nextID += 1
            return (id, exited, stdinHandle != nil)
        }

        guard hasStdin else { throw JSONRPCError.notStarted }
        guard !isExited else { throw JSONRPCError.processExited(stderrSummary()) }

        var message: [String: JSONValue] = ["id": .number(Double(id)), "method": .string(method), "params": params]
        if includeVersionField { message["jsonrpc"] = "2.0" }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONValue, Error>) in
                locked {
                    pending[id] = continuation
                    pendingMethods[id] = method
                }

                do {
                    try send(.object(message))
                } catch {
                    resolve(id: id, with: .failure(error))
                    return
                }

                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.resolve(id: id, with: .failure(JSONRPCError.timeout(method: method)))
                }
            }
        } onCancel: { [weak self] in
            self?.resolve(id: id, with: .failure(CancellationError()))
        }
    }

    /// 응답이 없는 알림을 보낸다.
    public func notify(_ method: String, params: JSONValue = [:]) throws {
        var message: [String: JSONValue] = ["method": .string(method), "params": params]
        if includeVersionField { message["jsonrpc"] = "2.0" }
        try send(.object(message))
    }

    /// stdin 을 닫고(대부분의 서버는 EOF 에서 종료) 프로세스를 정리한다.
    public func shutdown() {
        lock.lock()
        let process = self.process
        let stdinHandle = self.stdinHandle
        self.stdinHandle = nil
        self.process = nil
        lock.unlock()

        try? stdinHandle?.close()
        if let process {
            ProcessBox(process).terminate()
        }
        failAllPending(JSONRPCError.processExited("종료됨"))
    }

    // MARK: - 내부 처리

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func send(_ message: JSONValue) throws {
        var data = try message.encodedData()
        data.append(0x0A)
        lock.lock()
        let handle = stdinHandle
        lock.unlock()
        guard let handle else { throw JSONRPCError.notStarted }
        do {
            try handle.write(contentsOf: data)
        } catch {
            throw JSONRPCError.processExited("stdin 쓰기 실패: \(error.localizedDescription)")
        }
    }

    private func handleStdout(_ data: Data) {
        var lines: [Data] = []
        lock.lock()
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            lines.append(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        // 비정상적으로 긴 줄은 버린다 (메모리 보호).
        if buffer.count > 8 * 1024 * 1024 { buffer.removeAll() }
        lock.unlock()

        for line in lines where !line.isEmpty {
            guard let value = try? JSONDecoder().decode(JSONValue.self, from: Data(line)),
                  let id = value["id"]?.intValue
            else { continue } // 알림, 로그 줄 등은 무시한다.
            // 서버가 보내는 요청(method 포함)은 응답이 아니므로 건너뛴다.
            guard value["method"] == nil else { continue }
            let method = methodName(for: id)
            if let error = value["error"], error != .null {
                let message = error["message"]?.stringValue ?? "알 수 없는 오류"
                resolve(id: id, with: .failure(JSONRPCError.remote(method: method, message: message)))
            } else if let result = value["result"] {
                resolve(id: id, with: .success(result))
            } else {
                resolve(id: id, with: .failure(JSONRPCError.missingResult(method: method)))
            }
        }
    }

    private func appendStderr(_ data: Data) {
        lock.lock()
        stderrTail.append(data)
        if stderrTail.count > 4096 { stderrTail = stderrTail.suffix(4096) }
        lock.unlock()
    }

    private func stderrSummary() -> String {
        lock.lock()
        let text = String(decoding: stderrTail, as: UTF8.self)
        lock.unlock()
        return ProviderError.shorten(text, limit: 300)
    }

    private func handleExit() {
        lock.lock()
        exited = true
        lock.unlock()
        failAllPending(JSONRPCError.processExited(stderrSummary()))
    }

    private func methodName(for id: Int) -> String {
        lock.lock()
        defer { lock.unlock() }
        return pendingMethods[id] ?? "#\(id)"
    }

    private func resolve(id: Int, with result: Result<JSONValue, Error>) {
        lock.lock()
        let continuation = pending.removeValue(forKey: id)
        pendingMethods.removeValue(forKey: id)
        lock.unlock()
        continuation?.resume(with: result)
    }

    private func failAllPending(_ error: Error) {
        lock.lock()
        let continuations = Array(pending.values)
        pending.removeAll()
        pendingMethods.removeAll()
        lock.unlock()
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
    }
}

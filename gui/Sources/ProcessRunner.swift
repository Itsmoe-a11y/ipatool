import Foundation
import Darwin

/// ProcessExecutionError provides structured error reporting for CLI invocations.
public enum ProcessExecutionError: LocalizedError, Sendable {
    case binaryNotFound(searchedPaths: [String])
    case spawnFailed(code: Int32, path: String)
    case pipeCreationFailed
    case executionFailed(exitCode: Int32, output: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .binaryNotFound(let paths):
            return "ipatool-cli binary not found in candidate paths:\n" + paths.joined(separator: "\n")
        case .spawnFailed(let code, let path):
            return "posix_spawn failed for '\(path)' with error code: \(code) (\(String(cString: strerror(code))))"
        case .pipeCreationFailed:
            return "Failed to initialize communication pipes."
        case .executionFailed(let code, let output):
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                if code == 9 || code == 137 {
                    return "ipatool-cli was terminated by kernel signal SIGKILL (status 9). Apple Mobile File Integrity (AMFI) rejected code execution."
                } else if code == 10 || code == 138 {
                    return "ipatool-cli crashed with Bus Error (SIGBUS 10). Memory protection fault."
                } else if code == 11 || code == 139 {
                    return "ipatool-cli crashed with Segmentation Fault (SIGSEGV 11)."
                }
                return "Command exited with status \(code) (no output produced)."
            }
            return "Command exited with status \(code):\n\(trimmed)"
        case .cancelled:
            return "Process execution was cancelled by the user."
        }
    }
}

/// Thread-safe accumulator for captured process output data.
private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }

    func getString() -> String {
        lock.lock()
        defer { lock.unlock() }
        // Use lossy UTF-8 decoding to prevent dropping output on invalid bytes
        return String(decoding: data, as: UTF8.self)
    }
}

/// Thread-safe coordinator ensuring CheckedContinuation is resumed exactly once.
private final class ContinuationCoordinator<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var isResumed = false

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        continuation?.resume(returning: value)
        continuation = nil
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !isResumed else { return }
        isResumed = true
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

/// Actor and helper class that safely executes Mach-O binaries in TrollStore / jailbroken iOS
/// using posix_spawn with full asynchronous line-by-line streaming.
public final class ProcessRunner: Sendable {
    public static let shared = ProcessRunner()

    private var fileManager: FileManager { FileManager.default }
    private static let ansiRegex = try? NSRegularExpression(pattern: #"\x1b\[[0-9;]*[a-zA-Z]|\r"#, options: [])

    public init() {}

    /// Candidate binary paths in order of preference.
    public var candidateBinaryPaths: [String] {
        var paths: [String] = []

        // 1. App Bundle: embedded helper binary
        if let bundlePath = Bundle.main.bundleURL.appendingPathComponent("ipatool-cli").path as String? {
            paths.append(bundlePath)
        }
        if let bundleAlt = Bundle.main.bundleURL.appendingPathComponent("ipatool").path as String? {
            paths.append(bundleAlt)
        }

        // 2. /var/mobile root and Documents directory (user-installed or CLI builds)
        paths.append("/var/mobile/ipatool")
        paths.append("/var/mobile/ipatool-ios-arm64")
        paths.append("/var/mobile/ipatool-cli")
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            paths.append(docs.appendingPathComponent("ipatool-cli").path)
            paths.append(docs.appendingPathComponent("ipatool").path)
        }
        paths.append("/var/mobile/Documents/ipatool-cli")
        paths.append("/var/mobile/Documents/ipatool-ios-arm64")
        paths.append("/var/mobile/Documents/ipatool")

        // 3. Jailbreak / Rootless system bin paths
        paths.append("/var/jb/usr/bin/ipatool")
        paths.append("/var/jb/usr/local/bin/ipatool")
        paths.append("/usr/local/bin/ipatool")
        paths.append("/usr/bin/ipatool")

        return paths
    }

    /// Resolves the first valid binary path, making sure it has execute permissions.
    public func resolveExecutablePath() throws -> String {
        let searched = candidateBinaryPaths

        for path in searched {
            if fileManager.fileExists(atPath: path) {
                if !fileManager.isExecutableFile(atPath: path) {
                    chmod(path, 0o755)
                }
                return path
            }
        }

        throw ProcessExecutionError.binaryNotFound(searchedPaths: searched)
    }

    /// Checks if a valid executable binary exists on device.
    public func isExecutableAvailable() -> Bool {
        return (try? resolveExecutablePath()) != nil
    }

    /// Collects diagnostic details for debugging TrollStore environment.
    public func diagnosticInfo() -> [String: String] {
        var info: [String: String] = [:]
        do {
            let path = try resolveExecutablePath()
            info["Resolved Binary"] = path
            info["Exists"] = "true"
            info["Is Executable"] = fileManager.isExecutableFile(atPath: path) ? "true" : "false"

            let attrs = try? fileManager.attributesOfItem(atPath: path)
            if let size = attrs?[.size] as? Int64 {
                info["Size"] = "\(size) bytes"
            }
            if let perms = attrs?[.posixPermissions] as? NSNumber {
                info["Permissions"] = String(format: "%o", perms.intValue)
            }
        } catch {
            info["Resolved Binary"] = "None"
            info["Error"] = error.localizedDescription
        }

        info["Home Directory"] = NSHomeDirectory()
        info["Bundle Identifier"] = Bundle.main.bundleIdentifier ?? "Unknown"
        info["App Path"] = Bundle.main.bundlePath
        return info
    }

    /// Executes the binary with arguments, streaming lines in real time and returning output.
    @discardableResult
    public func run(
        args: [String],
        customEnvironment: [String: String]? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async throws -> CLIExecutionResult {
        try Task.checkCancellation()

        let startTime = Date()
        let binaryPath = try resolveExecutablePath()

        // Create pipes for stdout/stderr
        var stdoutPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0 else {
            throw ProcessExecutionError.pipeCreationFailed
        }

        // Set FD_CLOEXEC to prevent leaking descriptors into other concurrent spawns
        _ = fcntl(stdoutPipe[0], F_SETFD, FD_CLOEXEC)
        _ = fcntl(stdoutPipe[1], F_SETFD, FD_CLOEXEC)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        defer {
            posix_spawn_file_actions_destroy(&fileActions)
        }

        // Redirect stdout and stderr to the write end of our pipe
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[1])

        // Redirect stdin to /dev/null so child never hangs waiting for interactive terminal input
        posix_spawn_file_actions_addopen(&fileActions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)

        // Prepare arguments
        let fullArgs = [binaryPath] + args
        let cArgs: [UnsafeMutablePointer<CChar>?] = fullArgs.map { strdup($0) } + [nil]
        defer {
            for ptr in cArgs where ptr != nil { free(ptr) }
        }

        // Clean isolated environment variables
        var envDict: [String: String] = [
            "HOME": "/var/mobile",
            "PATH": "/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": NSTemporaryDirectory(),
            "USER": "mobile",
            "LOGNAME": "mobile",
            "SHELL": "/bin/sh",
            "LANG": "en_US.UTF-8"
        ]
        if let custom = customEnvironment {
            for (k, v) in custom { envDict[k] = v }
        }

        let cEnv: [UnsafeMutablePointer<CChar>?] = envDict.map { strdup("\($0)=\($1)") } + [nil]
        defer {
            for ptr in cEnv where ptr != nil { free(ptr) }
        }

        // Configure spawn attributes
        var attr: posix_spawnattr_t? = nil
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, binaryPath, &fileActions, &attr, cArgs, cEnv)

        // Always close write end in parent process so read encounters EOF when child terminates
        close(stdoutPipe[1])

        if spawnStatus != 0 {
            close(stdoutPipe[0])
            throw ProcessExecutionError.spawnFailed(code: spawnStatus, path: binaryPath)
        }

        let readFd = stdoutPipe[0]
        let outputAccumulator = OutputAccumulator()
        let cancellationBox = CancellationBox(pid: pid)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let coordinator = ContinuationCoordinator(continuation)
                cancellationBox.setCoordinator(coordinator)

                DispatchQueue.global(qos: .userInitiated).async {
                    defer {
                        // Ensure read descriptor is closed in reader thread
                        close(readFd)
                    }

                    var buffer = [UInt8](repeating: 0, count: 4096)
                    var lineBuffer = Data()

                    while true {
                        let bytesRead = read(readFd, &buffer, buffer.count)
                        if bytesRead < 0 {
                            if errno == EINTR {
                                continue // Interrupted by signal, retry read
                            }
                            break
                        } else if bytesRead == 0 {
                            break // Clean EOF
                        }

                        let chunk = Data(buffer[0..<bytesRead])
                        outputAccumulator.append(chunk)
                        lineBuffer.append(chunk)

                        // Process complete lines
                        while let newlineIndex = lineBuffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                            let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<newlineIndex)
                            lineBuffer.removeSubrange(lineBuffer.startIndex...newlineIndex)

                            // Robust lossy decoding prevents dropped lines on non-UTF8 bytes
                            let line = String(decoding: lineData, as: UTF8.self)
                            let cleanLine = Self.stripAnsiCodes(line)
                            if !cleanLine.isEmpty {
                                DispatchQueue.main.async {
                                    onLine?(cleanLine)
                                }
                            }
                        }
                    }

                    // Flush any remaining partial line
                    if !lineBuffer.isEmpty {
                        let line = String(decoding: lineBuffer, as: UTF8.self)
                        let cleanLine = Self.stripAnsiCodes(line)
                        if !cleanLine.isEmpty {
                            DispatchQueue.main.async {
                                onLine?(cleanLine)
                            }
                        }
                    }

                    // Wait for child process to exit and reap zombie
                    var exitStatus: Int32 = 0
                    var waitResult: pid_t = 0
                    repeat {
                        waitResult = waitpid(pid, &exitStatus, 0)
                    } while waitResult == -1 && errno == EINTR

                    // Cancel delayed SIGKILL immediately upon reaping to prevent PID reuse hazard
                    cancellationBox.markReaped()

                    let duration = Date().timeIntervalSince(startTime)
                    let fullOutput = outputAccumulator.getString()

                    if cancellationBox.isCancelled {
                        coordinator.resume(throwing: ProcessExecutionError.cancelled)
                        return
                    }

                    // Extract exit code
                    let code: Int32
                    if (exitStatus & 0x7f) == 0 {
                        code = (exitStatus >> 8) & 0xff
                    } else {
                        // Process terminated by signal
                        code = 128 + (exitStatus & 0x7f)
                    }

                    let result = CLIExecutionResult(output: fullOutput, exitCode: code, duration: duration)

                    if code == 0 {
                        coordinator.resume(returning: result)
                    } else {
                        coordinator.resume(throwing: ProcessExecutionError.executionFailed(exitCode: code, output: fullOutput))
                    }
                }
            }
        } onCancel: {
            cancellationBox.cancel()
        }
    }

    /// Asynchronous stream of stdout/stderr lines with complete cancellation support.
    public func stream(args: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    _ = try await self.run(args: args) { line in
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    if !(error is CancellationError) {
                        continuation.yield("Error: \(error.localizedDescription)")
                    }
                    continuation.finish()
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Helper to remove ANSI terminal color codes and progress carriage control.
    public static func stripAnsiCodes(_ text: String) -> String {
        guard !text.isEmpty, let regex = ansiRegex else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}

/// Helper managing cancellation signals, SIGKILL timeouts, and PID recycling mitigation.
private final class CancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private let pid: pid_t
    private(set) var isCancelled = false
    private var isReaped = false
    private var sigkillWorkItem: DispatchWorkItem?
    private var coordinator: ContinuationCoordinator<CLIExecutionResult>?

    init(pid: pid_t) {
        self.pid = pid
    }

    func setCoordinator(_ coordinator: ContinuationCoordinator<CLIExecutionResult>) {
        lock.lock()
        defer { lock.unlock() }
        self.coordinator = coordinator
        if isCancelled {
            coordinator.resume(throwing: ProcessExecutionError.cancelled)
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }
        isCancelled = true

        coordinator?.resume(throwing: ProcessExecutionError.cancelled)

        guard !isReaped, pid > 0 else {
            lock.unlock()
            return
        }

        // Deliver SIGTERM first
        kill(pid, SIGTERM)

        // Schedule fallback SIGKILL wrapped in a cancellable DispatchWorkItem
        let workItem = DispatchWorkItem { [pid] in
            kill(pid, SIGKILL)
        }
        sigkillWorkItem = workItem
        lock.unlock()

        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    func markReaped() {
        lock.lock()
        defer { lock.unlock() }
        isReaped = true
        // Cancel fallback kill immediately so recycled PID is never killed
        sigkillWorkItem?.cancel()
        sigkillWorkItem = nil
    }
}

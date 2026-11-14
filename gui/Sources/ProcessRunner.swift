import Foundation
import Darwin

/// ProcessExecutionError provides structured error reporting for CLI invocations.
public enum ProcessExecutionError: LocalizedError {
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
            return "Command exited with status \(code):\n\(output)"
        case .cancelled:
            return "Process execution was cancelled by the user."
        }
    }
}

/// Actor and helper class that safely executes Mach-O binaries in TrollStore / jailbroken iOS
/// using posix_spawn with full asynchronous line-by-line streaming.
public final class ProcessRunner {
    public static let shared = ProcessRunner()

    private let fileManager = FileManager.default

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

        // 2. Documents directory (for user updates or side-loaded binaries)
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            paths.append(docs.appendingPathComponent("ipatool-cli").path)
            paths.append(docs.appendingPathComponent("ipatool").path)
        }
        paths.append("/var/mobile/Documents/ipatool-cli")
        paths.append("/var/mobile/Documents/ipatool-ios-arm64")

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
                // Ensure executable permission bit is set
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
        onLine: ((String) -> Void)? = nil
    ) async throws -> CLIExecutionResult {
        let startTime = Date()
        let binaryPath = try resolveExecutablePath()

        // Create pipes for stdout/stderr
        var stdoutPipe: [Int32] = [0, 0]
        guard pipe(&stdoutPipe) == 0 else {
            throw ProcessExecutionError.pipeCreationFailed
        }

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, stdoutPipe[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[0])
        posix_spawn_file_actions_addclose(&fileActions, stdoutPipe[1])

        // Prepare arguments
        let fullArgs = [binaryPath] + args
        let cArgs: [UnsafeMutablePointer<CChar>?] = fullArgs.map { strdup($0) } + [nil]
        defer {
            for ptr in cArgs where ptr != nil {
                free(ptr)
            }
        }

        // Configure environment variables for TrollStore / iOS runtime
        var envDict = ProcessInfo.processInfo.environment
        envDict["HOME"] = "/var/mobile"
        envDict["PATH"] = "/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (envDict["PATH"] ?? "")
        envDict["TMPDIR"] = NSTemporaryDirectory()
        if let custom = customEnvironment {
            for (k, v) in custom {
                envDict[k] = v
            }
        }

        let cEnv: [UnsafeMutablePointer<CChar>?] = envDict.map { strdup("\($0)=\($1)") } + [nil]
        defer {
            for ptr in cEnv where ptr != nil {
                free(ptr)
            }
        }

        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        var defaultSignals = sigset_t()
        sigemptyset(&defaultSignals)
        posix_spawnattr_setsigdefault(&attr, &defaultSignals)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGDEF))
        defer { posix_spawnattr_destroy(&attr) }

        var pid: pid_t = 0
        let spawnStatus = posix_spawn(&pid, binaryPath, &fileActions, &attr, cArgs, cEnv)
        posix_spawn_file_actions_destroy(&fileActions)

        // Close write end in parent process so read encounters EOF when child exits
        close(stdoutPipe[1])

        if spawnStatus != 0 {
            close(stdoutPipe[0])
            throw ProcessExecutionError.spawnFailed(code: spawnStatus, path: binaryPath)
        }

        let readFd = stdoutPipe[0]
        let closeLock = NSLock()
        var isFdClosed = false
        let safeCloseReadFd = {
            closeLock.lock()
            defer { closeLock.unlock() }
            if !isFdClosed {
                close(readFd)
                isFdClosed = true
            }
        }

        // Read pipe asynchronously in a background dispatch queue
        let outputAccumulator = OutputAccumulator()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    var lineBuffer = Data()

                    while true {
                        let bytesRead = read(readFd, &buffer, buffer.count)
                        if bytesRead <= 0 {
                            break
                        }

                        let chunk = Data(buffer[0..<bytesRead])
                        outputAccumulator.append(chunk)

                        // Process lines incrementally
                        lineBuffer.append(chunk)
                        while let newlineIndex = lineBuffer.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
                            let lineData = lineBuffer.subdata(in: 0..<newlineIndex)
                            lineBuffer.removeSubrange(0...newlineIndex)

                            if let line = String(data: lineData, encoding: .utf8), !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let cleanLine = Self.stripAnsiCodes(line)
                                if !cleanLine.isEmpty {
                                    DispatchQueue.main.async {
                                        onLine?(cleanLine)
                                    }
                                }
                            }
                        }
                    }

                    // Flush any remaining partial line
                    if !lineBuffer.isEmpty, let line = String(data: lineBuffer, encoding: .utf8) {
                        let cleanLine = Self.stripAnsiCodes(line)
                        if !cleanLine.isEmpty {
                            DispatchQueue.main.async {
                                onLine?(cleanLine)
                            }
                        }
                    }

                    safeCloseReadFd()

                    var exitStatus: Int32 = 0
                    var waitResult: pid_t = 0
                    repeat {
                        waitResult = waitpid(pid, &exitStatus, 0)
                    } while waitResult == -1 && errno == EINTR

                    // Extract actual exit code
                    let code: Int32
                    if (exitStatus & 0x7f) == 0 {
                        code = (exitStatus >> 8) & 0xff
                    } else {
                        code = exitStatus
                    }

                    let duration = Date().timeIntervalSince(startTime)
                    let fullOutput = outputAccumulator.getString()

                    let result = CLIExecutionResult(output: fullOutput, exitCode: code, duration: duration)

                    if code == 0 {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: ProcessExecutionError.executionFailed(exitCode: code, output: fullOutput))
                    }
                }
            }
        } onCancel: {
            if pid > 0 {
                kill(pid, SIGTERM)
                // Fallback force kill after 1 second
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                    kill(pid, SIGKILL)
                }
            }
            safeCloseReadFd()
        }
    }

    /// Asynchronous stream of stdout/stderr lines.
    public func stream(args: [String]) -> AsyncStream<String> {
        AsyncStream { continuation in
            Task {
                do {
                    _ = try await self.run(args: args) { line in
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.yield("Error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    /// Helper to remove ANSI terminal color codes and progress carriage control.
    public static func stripAnsiCodes(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let pattern = #"\x1b\[[0-9;]*[a-zA-Z]|\r"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        return text
    }
}

/// Thread-safe accumulator for captured process output data.
private final class OutputAccumulator {
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
        return String(data: data, encoding: .utf8) ?? ""
    }
}

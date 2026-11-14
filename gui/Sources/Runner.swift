import Foundation

enum CommandRunner {
    static func run(args: [String]) -> (output: String, exitCode: Int32) {
        let bundleBin = Bundle.main.bundleURL.appendingPathComponent("ipatool-cli").path
        let path: String
        if FileManager.default.isExecutableFile(atPath: bundleBin) {
            path = bundleBin
        } else if FileManager.default.fileExists(atPath: bundleBin) {
            chmod(bundleBin, 0o755)
            path = bundleBin
        } else if FileManager.default.fileExists(atPath: "/var/jb/usr/bin/ipatool") {
            path = "/var/jb/usr/bin/ipatool"
        } else if FileManager.default.fileExists(atPath: "/var/mobile/Documents/ipatool-ios-arm64") {
            path = "/var/mobile/Documents/ipatool-ios-arm64"
        } else {
            path = bundleBin
        }

        var pipedes: [Int32] = [0, 0]
        pipe(&pipedes)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)
        posix_spawn_file_actions_adddup2(&fileActions, pipedes[1], STDOUT_FILENO)
        posix_spawn_file_actions_adddup2(&fileActions, pipedes[1], STDERR_FILENO)
        posix_spawn_file_actions_addclose(&fileActions, pipedes[0])
        posix_spawn_file_actions_addclose(&fileActions, pipedes[1])

        let fullArgs = [path] + args
        let cArgs = fullArgs.map { strdup($0) } + [nil]
        defer {
            for ptr in cArgs where ptr != nil {
                free(ptr)
            }
        }

        var pid: pid_t = 0
        setenv("HOME", "/var/mobile", 0)
        let status = posix_spawn(&pid, path, &fileActions, nil, cArgs, environ)
        posix_spawn_file_actions_destroy(&fileActions)
        close(pipedes[1])

        if status != 0 {
            close(pipedes[0])
            return ("Error: posix_spawn failed with code \(status)", status)
        }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let bytesRead = read(pipedes[0], &buffer, bufferSize)
            if bytesRead <= 0 { break }
            data.append(buffer, count: bytesRead)
        }
        close(pipedes[0])

        var exitStatus: Int32 = 0
        waitpid(pid, &exitStatus, 0)
        let output = String(data: data, encoding: .utf8) ?? ""
        return (output, exitStatus)
    }
}

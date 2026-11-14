import SwiftUI

@main
public struct IPAToolApp: App {
    public init() {
        configureApplicationEnvironment()
    }

    public var body: some Scene {
        WindowGroup {
            MainTabView()
        }
    }

    private func configureApplicationEnvironment() {
        // 1. Ensure download directories exist
        let fileManager = FileManager.default
        if let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let ipaDir = docs.appendingPathComponent("IPAs", isDirectory: true)
            if !fileManager.fileExists(atPath: ipaDir.path) {
                try? fileManager.createDirectory(at: ipaDir, withIntermediateDirectories: true, attributes: nil)
            }
        }

        // 2. Proactively resolve and verify permissions of ipatool-cli binary
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let resolved = try ProcessRunner.shared.resolveExecutablePath()
                print("[IPAToolApp] Successfully verified executable binary at: \(resolved)")
            } catch {
                print("[IPAToolApp] Warning during startup executable check: \(error.localizedDescription)")
            }
        }
    }
}

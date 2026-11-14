import Foundation
import UIKit
import Combine

@MainActor
public final class DownloadsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var activeDownloads: [DownloadTask] = []
    @Published public var downloadedIPAs: [DownloadedIPA] = []
    @Published public var liveLogs: [LogEntry] = []
    @Published public var isDownloading: Bool = false
    @Published public var storageUsedFormatted: String = "0 MB"

    // UI Presentation triggers
    @Published public var shareURL: URL? = nil
    @Published public var alertMessage: String? = nil
    @Published public var selectedTab: Int = 0 // 0 = Active, 1 = Storage

    private let processRunner = ProcessRunner.shared
    private let fileManager = FileManager.default

    public init() {
        createDownloadDirectories()
        refreshDownloadedIPAs()
    }

    // MARK: - Download Directory Setup
    public var downloadDirectory: URL {
        let paths = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
        let docs = paths[0]
        let ipaDir = docs.appendingPathComponent("IPAs", isDirectory: true)
        if !fileManager.fileExists(atPath: ipaDir.path) {
            try? fileManager.createDirectory(at: ipaDir, withIntermediateDirectories: true, attributes: nil)
        }
        return ipaDir
    }

    private func createDownloadDirectories() {
        _ = downloadDirectory
        // Also create /var/mobile/Documents/IPAs if running in TrollStore rootless environment
        let mobileDocs = URL(fileURLWithPath: "/var/mobile/Documents/IPAs")
        if !fileManager.fileExists(atPath: mobileDocs.path) {
            try? fileManager.createDirectory(at: mobileDocs, withIntermediateDirectories: true, attributes: nil)
        }
    }

    // MARK: - Start Download Action
    public func startDownload(app: AppItem, versionId: Int64? = nil, purchase: Bool = false) {
        let task = DownloadTask(app: app, versionId: versionId)
        activeDownloads.insert(task, at: 0)
        let taskId = task.id

        isDownloading = true
        appendLog("Initiating download for '\(app.name)' (\(app.bundleIdentifier))...", level: .info, taskId: taskId)

        Task { [weak self] in
            guard let self = self else { return }

            var args = [
                "--keychain-passphrase", "ipatool-ios-keyring",
                "--non-interactive",
                "download",
                "--bundle-identifier", app.bundleIdentifier,
                "--output", self.downloadDirectory.path,
                "--verbose"
            ]

            if let vId = versionId {
                args += ["--external-version-id", "\(vId)"]
                self.appendLog("Targeting specific external version ID: \(vId)", level: .info, taskId: taskId)
            }

            if purchase {
                args.append("--purchase")
                self.appendLog("Included --purchase flag for App Store license acquisition.", level: .info, taskId: taskId)
            }

            do {
                let result = try await self.processRunner.run(args: args) { [weak self] line in
                    Task { @MainActor [weak self] in
                        self?.parseDownloadLine(line, taskId: taskId)
                    }
                }

                self.appendLog("ipatool command completed successfully in \(String(format: "%.1f", result.duration))s.", level: .success, taskId: taskId)

                // Locate the downloaded IPA file in the directory
                if let ipaURL = self.locateDownloadedFile(for: app) {
                    self.updateTaskStatus(taskId: taskId, status: .completed(outputURL: ipaURL))
                    self.appendLog("Saved IPA file to: \(ipaURL.lastPathComponent)", level: .success, taskId: taskId)
                } else {
                    self.updateTaskStatus(taskId: taskId, status: .completed(outputURL: self.downloadDirectory))
                }

                self.refreshDownloadedIPAs()
                self.isDownloading = self.activeDownloads.contains(where: { !$0.status.isTerminal })
            } catch {
                let errorMsg = error.localizedDescription
                self.appendLog("Download failed: \(errorMsg)", level: .error, taskId: taskId)
                self.updateTaskStatus(taskId: taskId, status: .failed(message: errorMsg))
                self.isDownloading = self.activeDownloads.contains(where: { !$0.status.isTerminal })
            }
        }
    }

    // MARK: - Line-by-Line Parsing for Progress & Status
    private func parseDownloadLine(_ rawLine: String, taskId: UUID) {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }

        // If this line is a live progress frame, update task progress without flooding logs
        if let progress = extractPercentage(from: line) {
            updateTaskStatus(taskId: taskId, status: .downloading(progress: progress, speed: extractSpeed(from: line)))
            return
        }

        // Determine log level cleanly
        var level: LogLevel = .info
        let lower = line.lowercased()
        if lower.contains("error") || lower.hasPrefix("err ") || lower.contains("failed") {
            level = .error
        } else if lower.contains("warn") {
            level = .warn
        } else if lower.contains("success") || lower.contains("finished") || lower.contains("done") {
            level = .success
        }

        appendLog(line, level: level, taskId: taskId)
    }

    private func extractPercentage(from text: String) -> Double? {
        let pattern = #"(\d{1,3}(?:\.\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: text),
           let value = Double(text[range]) {
            return min(max(value / 100.0, 0.0), 1.0)
        }
        return nil
    }

    private func extractSpeed(from text: String) -> String {
        let pattern = #"(\d+(?:\.\d+)?\s*(?:KB|MB|GB)/s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return "" }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = regex.firstMatch(in: text, options: [], range: nsRange),
           let range = Range(match.range(at: 1), in: text) {
            return String(text[range])
        }
        return ""
    }

    private func updateTaskStatus(taskId: UUID, status: DownloadStatus) {
        if let index = activeDownloads.firstIndex(where: { $0.id == taskId }) {
            activeDownloads[index].status = status
        }
    }

    private func appendLog(_ message: String, level: LogLevel = .info, taskId: UUID? = nil) {
        let entry = LogEntry(message: message, level: level)
        liveLogs.append(entry)
        if liveLogs.count > 1000 {
            liveLogs.removeFirst(100)
        }

        if let id = taskId, let index = activeDownloads.firstIndex(where: { $0.id == id }) {
            activeDownloads[index].logs.append(entry)
        }
    }

    // MARK: - Locate Downloaded IPA in Directory
    private func locateDownloadedFile(for app: AppItem) -> URL? {
        guard let files = try? fileManager.contentsOfDirectory(at: downloadDirectory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else {
            return nil
        }

        // Look for .ipa files created/modified in the last 2 minutes
        let ipaFiles = files.filter { $0.pathExtension.lowercased() == "ipa" }
        let sorted = ipaFiles.sorted {
            let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return d1 > d2
        }

        // Match by bundle identifier if filename contains it
        if let match = sorted.first(where: { $0.lastPathComponent.lowercased().contains(app.bundleIdentifier.lowercased()) }) {
            return match
        }

        return sorted.first
    }

    // MARK: - Storage Manager: List All Downloaded IPAs
    public func refreshDownloadedIPAs() {
        var ipas: [DownloadedIPA] = []
        var totalBytes: Int64 = 0

        let searchDirs = [
            downloadDirectory,
            URL(fileURLWithPath: "/var/mobile/Documents/IPAs")
        ]

        var seenPaths = Set<String>()

        for dir in searchDirs {
            guard fileManager.fileExists(atPath: dir.path),
                  let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey], options: .skipsHiddenFiles) else {
                continue
            }

            for url in contents where url.pathExtension.lowercased() == "ipa" {
                if !seenPaths.contains(url.path) {
                    seenPaths.insert(url.path)
                    let ipa = DownloadedIPA(url: url)
                    ipas.append(ipa)
                    totalBytes += ipa.fileSizeBytes
                }
            }
        }

        self.downloadedIPAs = ipas.sorted(by: { $0.creationDate > $1.creationDate })

        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        self.storageUsedFormatted = formatter.string(fromByteCount: totalBytes)
    }

    // MARK: - Delete IPA Action
    public func deleteIPA(_ ipa: DownloadedIPA) {
        do {
            try fileManager.removeItem(at: ipa.url)
            appendLog("Deleted IPA file: \(ipa.fileName)", level: .info)
            refreshDownloadedIPAs()
        } catch {
            alertMessage = "Failed to delete IPA: \(error.localizedDescription)"
        }
    }

    // MARK: - Install / Open in TrollStore Action
    public func openInTrollStore(_ ipa: DownloadedIPA) {
        let fileURL = ipa.url

        guard fileManager.fileExists(atPath: fileURL.path) else {
            appendLog("Error: IPA file no longer exists at \(fileURL.path)", level: .error)
            return
        }

        // TrollStore URL scheme: apple-magnifier://install?url=...
        var components = URLComponents(string: "apple-magnifier://install")
        components?.queryItems = [URLQueryItem(name: "url", value: fileURL.path)]

        if let trollStoreURL = components?.url, UIApplication.shared.canOpenURL(trollStoreURL) {
            UIApplication.shared.open(trollStoreURL, options: [:]) { [weak self] success in
                if success {
                    self?.appendLog("Opened '\(ipa.fileName)' directly in TrollStore installer.", level: .success)
                } else {
                    self?.triggerShareSheet(url: fileURL)
                }
            }
        } else {
            // Present native UIActivityViewController to choose TrollStore or other apps
            triggerShareSheet(url: fileURL)
        }
    }

    public func triggerShareSheet(url: URL) {
        self.shareURL = url
    }

    public func clearLogs() {
        liveLogs.removeAll()
    }
}

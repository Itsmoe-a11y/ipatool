import Foundation
import Combine

@MainActor
public final class SearchViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var query: String = ""
    @Published public var results: [AppItem] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil

    // Detail & Historical Versions
    @Published public var selectedApp: AppItem? = nil
    @Published public var historicalVersions: [Int64] = []
    @Published public var versionMetadataCache: [Int64: AppVersionItem] = [:]
    @Published public var isLoadingVersions: Bool = false
    @Published public var versionsError: String? = nil
    @Published public var isShowingVersionsSheet: Bool = false

    // Platform filter
    @Published public var selectedPlatform: String = "iphone" // iphone, ipad, macos

    // MARK: - Private State
    private var searchTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()
    private let processRunner = ProcessRunner.shared

    public init() {
        setupDebounce()
    }

    // MARK: - Live Debounced Search Setup
    private func setupDebounce() {
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(450), scheduler: RunLoop.main)
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    self.searchTask?.cancel()
                    self.results = []
                    self.errorMessage = nil
                    self.isLoading = false
                } else if trimmed.count >= 2 {
                    self.performSearch(term: trimmed)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Trigger Search
    public func performSearch(term: String? = nil) {
        let searchTerm = (term ?? query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchTerm.isEmpty else { return }

        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self = self else { return }
            self.isLoading = true
            self.errorMessage = nil

            do {
                // Try iTunes Search API first for instant, high-resolution artwork and ratings
                let apps = try await self.searchViaITunes(term: searchTerm)
                if !Task.isCancelled {
                    self.results = apps
                    self.isLoading = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                // Fallback to ipatool search CLI
                do {
                    let apps = try await self.searchViaCli(term: searchTerm)
                    if !Task.isCancelled {
                        self.results = apps
                        self.isLoading = false
                    }
                } catch let cliErr {
                    if !Task.isCancelled {
                        self.errorMessage = "Search failed: \(cliErr.localizedDescription)"
                        self.isLoading = false
                    }
                }
            }
        }
    }

    // MARK: - Direct iTunes API Search (Rich Metadata & Icons)
    private func searchViaITunes(term: String) async throws -> [AppItem] {
        var components = URLComponents(string: "https://itunes.apple.com/search")
        components?.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "country", value: "US")
        ]

        guard let url = components?.url else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10.0
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(iTunesSearchResponse.self, from: data)
        return decoded.results
    }

    // MARK: - ipatool CLI Search Fallback
    private func searchViaCli(term: String) async throws -> [AppItem] {
        var args = [
            "--keychain-passphrase", "ipatool-ios-keyring",
            "--non-interactive",
            "search", term,
            "--limit", "20",
            "--format", "json"
        ]
        if !selectedPlatform.isEmpty && selectedPlatform != "iphone" {
            args += ["--platform", selectedPlatform]
        }

        let result = try await processRunner.run(args: args)

        // Parse JSON output from ipatool
        return parseAppsFromCLIOutput(result.output)
    }

    private func parseAppsFromCLIOutput(_ output: String) -> [AppItem] {
        var parsedApps: [AppItem] = []

        // Try decoding as single IPAToolSearchResult object
        if let data = output.data(using: .utf8),
           let directResult = try? JSONDecoder().decode(IPAToolSearchResult.self, from: data),
           let apps = directResult.apps {
            return apps
        }

        // Try decoding line-delimited JSON (Zerolog lines)
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{") && trimmed.hasSuffix("}"),
                  let data = trimmed.data(using: .utf8) else { continue }

            if let result = try? JSONDecoder().decode(IPAToolSearchResult.self, from: data),
               let apps = result.apps, !apps.isEmpty {
                let validApps = apps.filter { $0.id != 0 && !$0.bundleIdentifier.isEmpty }
                parsedApps.append(contentsOf: validApps)
            } else if let app = try? JSONDecoder().decode(AppItem.self, from: data) {
                if app.id != 0 && !app.bundleIdentifier.isEmpty {
                    parsedApps.append(app)
                }
            }
        }

        return parsedApps
    }

    // MARK: - Fetch Historical Version Identifiers
    public func fetchHistoricalVersions(for app: AppItem) async {
        self.isLoadingVersions = true
        self.versionsError = nil
        self.historicalVersions = []

        let bundleId = app.bundleIdentifier
        let appId = app.id

        var args = [
            "--keychain-passphrase", "ipatool-ios-keyring",
            "--non-interactive",
            "list-versions",
            "--format", "json"
        ]
        if !bundleId.isEmpty {
            args += ["--bundle-identifier", bundleId]
        } else {
            args += ["--app-id", "\(appId)"]
        }

        do {
            let result = try await processRunner.run(args: args)
            let versions = parseVersionsFromCLIOutput(result.output)

            if versions.isEmpty {
                self.versionsError = "No historical version IDs returned by App Store."
            } else {
                // Sort descending: latest versions at the top
                let sorted = versions.sorted(by: >)
                self.historicalVersions = sorted

                // Prefetch human-readable metadata for top recent versions in background
                Task {
                    for vId in sorted.prefix(5) {
                        await self.resolveVersionMetadata(for: app, versionId: vId)
                    }
                }
            }
            self.isLoadingVersions = false
        } catch {
            self.versionsError = error.localizedDescription
            self.isLoadingVersions = false
        }
    }

    // MARK: - Resolve Human-Readable Version Metadata via get-version-metadata
    public func resolveVersionMetadata(for app: AppItem, versionId: Int64) async {
        if let existing = versionMetadataCache[versionId], existing.displayVersion != nil {
            return
        }

        var item = versionMetadataCache[versionId] ?? AppVersionItem(externalVersionId: versionId)
        item.isLoadingMetadata = true
        versionMetadataCache[versionId] = item

        var args = [
            "--keychain-passphrase", "ipatool-ios-keyring",
            "--non-interactive",
            "get-version-metadata",
            "--external-version-id", "\(versionId)",
            "--format", "json"
        ]
        if !app.bundleIdentifier.isEmpty {
            args += ["--bundle-identifier", app.bundleIdentifier]
        } else {
            args += ["--app-id", "\(app.id)"]
        }

        do {
            let result = try await processRunner.run(args: args)
            if let parsed = parseVersionMetadataOutput(result.output) {
                var updated = item
                updated.displayVersion = parsed.displayVersion
                updated.releaseDate = parsed.formattedDate
                updated.isLoadingMetadata = false
                versionMetadataCache[versionId] = updated
            } else {
                var updated = item
                updated.isLoadingMetadata = false
                updated.metadataError = "Metadata not found"
                versionMetadataCache[versionId] = updated
            }
        } catch {
            var updated = item
            updated.isLoadingMetadata = false
            updated.metadataError = error.localizedDescription
            versionMetadataCache[versionId] = updated
        }
    }

    private func parseVersionMetadataOutput(_ output: String) -> (displayVersion: String?, formattedDate: String?)? {
        struct MetaJSON: Codable {
            let externalVersionID: String?
            let displayVersion: String?
            let releaseDate: String?
        }

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let data = trimmed.data(using: .utf8) else { continue }
            if let decoded = try? JSONDecoder().decode(MetaJSON.self, from: data),
               let ver = decoded.displayVersion, !ver.isEmpty {
                var dateStr: String? = nil
                if let rDate = decoded.releaseDate {
                    let iso = ISO8601DateFormatter()
                    if let d = iso.date(from: rDate) {
                        let df = DateFormatter()
                        df.dateStyle = .medium
                        dateStr = df.string(from: d)
                    } else {
                        dateStr = String(rDate.prefix(10))
                    }
                }
                return (ver, dateStr)
            }
        }

        // Regex fallback for displayVersion
        let pattern = #""displayVersion"\s*:\s*"([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: output, options: [], range: NSRange(output.startIndex..<output.endIndex, in: output)),
           let range = Range(match.range(at: 1), in: output) {
            let ver = String(output[range])
            return (ver, nil)
        }

        return nil
    }

    private func parseVersionsFromCLIOutput(_ output: String) -> [Int64] {
        var versionIds: Set<Int64> = []

        // Try decoding full VersionListResult JSON
        if let data = output.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(VersionListResult.self, from: data),
           let list = decoded.externalVersionIdentifiers {
            return list
        }

        // Try line-by-line parsing
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let data = trimmed.data(using: .utf8) else { continue }

            if let decoded = try? JSONDecoder().decode(VersionListResult.self, from: data),
               let list = decoded.externalVersionIdentifiers {
                versionIds.formUnion(list)
            }
        }

        // Regex fallback if JSON contains nested numbers or text output
        if versionIds.isEmpty {
            let pattern = #"\b([0-9]{8,10})\b"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let range = NSRange(output.startIndex..<output.endIndex, in: output)
                let matches = regex.matches(in: output, options: [], range: range)
                for match in matches {
                    if let r = Range(match.range, in: output), let id = Int64(output[r]) {
                        versionIds.insert(id)
                    }
                }
            }
        }

        return Array(versionIds)
    }

    public func selectApp(_ app: AppItem) {
        self.selectedApp = app
        self.historicalVersions = []
        self.versionMetadataCache = [:]
        self.versionsError = nil
    }
}

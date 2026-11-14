import SwiftUI
import UIKit

struct MainTabView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
            DownloadsView()
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
            AccountView()
                .tabItem {
                    Label("Account", systemImage: "person.circle")
                }
        }
    }
}

// MARK: - Search View
struct SearchView: View {
    @State private var query = ""
    @State private var apps: [AppItem] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedApp: AppItem?

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    TextField("Search App Store (e.g. AcuraLink)", text: $query)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    if isSearching {
                        ProgressView()
                            .padding(.leading, 8)
                    } else {
                        Button("Search") {
                            searchApps()
                        }
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding()

                if let err = errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                List(apps) { app in
                    Button(action: {
                        selectedApp = app
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(app.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            Text(app.bundleIdentifier)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("ID: \(String(app.id))")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("IPATool")
            .sheet(item: $selectedApp) { app in
                AppDetailSheet(app: app)
            }
        }
    }

    private func searchApps() {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        apps = []

        DispatchQueue.global(qos: .userInitiated).async {
            let res = CommandRunner.run(args: ["search", term])
            DispatchQueue.main.async {
                isSearching = false
                if res.exitCode != 0 {
                    errorMessage = res.output.isEmpty ? "Search failed with exit code \(res.exitCode)" : res.output
                    return
                }

                // Parse apps from output
                var parsed: [AppItem] = []
                for line in res.output.components(separatedBy: .newlines) {
                    if line.contains("\"apps\""), let data = line.data(using: .utf8) {
                        if let decoded = try? JSONDecoder().decode(SearchResult.self, from: data), let found = decoded.apps {
                            parsed = found
                            break
                        }
                    }
                }
                if parsed.isEmpty {
                    errorMessage = "No apps found or failed to parse results."
                } else {
                    apps = parsed
                }
            }
        }
    }
}

// MARK: - App Detail Sheet (Versions & Download)
struct AppDetailSheet: View {
    let app: AppItem
    @Environment(\.presentationMode) var presentationMode
    @State private var isDownloading = false
    @State private var downloadStatus: String?
    @State private var versionIDs: [Int64] = []
    @State private var isLoadingVersions = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("App Info")) {
                    Text(app.name).font(.headline)
                    Text("Bundle ID: \(app.bundleIdentifier)").font(.footnote)
                    Text("App ID: \(String(app.id))").font(.footnote)
                }

                Section(header: Text("Latest Version")) {
                    Button(action: downloadLatest) {
                        HStack {
                            Image(systemName: "arrow.down.app.fill")
                            Text("Download Latest Version")
                        }
                    }
                    .disabled(isDownloading)
                }

                Section(header: Text("Historical Versions")) {
                    if isLoadingVersions {
                        HStack {
                            ProgressView()
                            Text("Fetching available versions...").font(.footnote).foregroundColor(.secondary)
                        }
                    } else if versionIDs.isEmpty {
                        Button("Load All Version IDs") {
                            loadVersions()
                        }
                    } else {
                        ForEach(versionIDs, id: \.self) { vid in
                            HStack {
                                Text("Version ID: \(String(vid))")
                                    .font(.system(.body, design: .monospaced))
                                Spacer()
                                Button("Get") {
                                    downloadSpecific(versionID: vid)
                                }
                                .buttonStyle(BorderlessButtonStyle())
                                .disabled(isDownloading)
                            }
                        }
                    }
                }

                if let status = downloadStatus {
                    Section(header: Text("Status")) {
                        Text(status)
                            .font(.footnote)
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle(app.name)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }

    private func downloadLatest() {
        isDownloading = true
        downloadStatus = "Downloading latest version..."

        DispatchQueue.global(qos: .userInitiated).async {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sanitized = app.name.replacingOccurrences(of: " ", with: "_")
            let outPath = docs.appendingPathComponent("\(sanitized)_latest.ipa").path

            let res = CommandRunner.run(args: ["download", "-b", app.bundleIdentifier, "--purchase", "--output", outPath])
            DispatchQueue.main.async {
                isDownloading = false
                if res.exitCode == 0 {
                    downloadStatus = "Successfully downloaded to Downloads tab!"
                } else {
                    downloadStatus = "Failed: \(res.output)"
                }
            }
        }
    }

    private func downloadSpecific(versionID: Int64) {
        isDownloading = true
        downloadStatus = "Downloading version ID \(versionID)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let sanitized = app.name.replacingOccurrences(of: " ", with: "_")
            let outPath = docs.appendingPathComponent("\(sanitized)_\(versionID).ipa").path

            let res = CommandRunner.run(args: ["download", "-b", app.bundleIdentifier, "--external-version-id", String(versionID), "--output", outPath])
            DispatchQueue.main.async {
                isDownloading = false
                if res.exitCode == 0 {
                    downloadStatus = "Successfully downloaded to Downloads tab!"
                } else {
                    downloadStatus = "Failed: \(res.output)"
                }
            }
        }
    }

    private func loadVersions() {
        isLoadingVersions = true
        DispatchQueue.global(qos: .userInitiated).async {
            let res = CommandRunner.run(args: ["list-versions", "-b", app.bundleIdentifier])
            DispatchQueue.main.async {
                isLoadingVersions = false
                var foundIDs: [Int64] = []
                for line in res.output.components(separatedBy: .newlines) {
                    if line.contains("externalVersionIdentifiers"), let data = line.data(using: .utf8) {
                        if let decoded = try? JSONDecoder().decode(VersionListResult.self, from: data), let ids = decoded.externalVersionIdentifiers {
                            foundIDs = ids
                            break
                        }
                    }
                }
                // Fallback: search for integer tokens
                if foundIDs.isEmpty {
                    let numbers = res.output.components(separatedBy: CharacterSet.whitespacesAndNewlines).compactMap { Int64($0) }
                    if !numbers.isEmpty {
                        foundIDs = numbers
                    }
                }
                versionIDs = foundIDs.reversed() // newest first
            }
        }
    }
}

// MARK: - Downloads View
struct DownloadsView: View {
    @State private var ipas: [DownloadedIPA] = []
    @State private var shareURL: URL?

    var body: some View {
        NavigationView {
            List {
                if ipas.isEmpty {
                    Text("No downloaded IPAs found yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(ipas) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name).font(.headline)
                                Text(item.sizeString).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Share / Install") {
                                shareURL = item.url
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                    }
                    .onDelete(perform: deleteIPA)
                }
            }
            .navigationTitle("Downloads")
            .navigationBarItems(trailing: Button(action: refreshIPAs) {
                Image(systemName: "arrow.clockwise")
            })
            .sheet(item: Binding<DownloadedIPA?>(
                get: { shareURL.map { DownloadedIPA(url: $0, name: $0.lastPathComponent, sizeString: "") } },
                set: { shareURL = $0?.url }
            )) { item in
                ShareSheet(items: [item.url])
            }
            .onAppear(perform: refreshIPAs)
        }
    }

    private func refreshIPAs() {
        var found: [DownloadedIPA] = []
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: [.fileSizeKey]) {
            for f in files where f.pathExtension.lowercased() == "ipa" {
                let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                let formatted = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                found.append(DownloadedIPA(url: f, name: f.lastPathComponent, sizeString: formatted))
            }
        }
        ipas = found
    }

    private func deleteIPA(at offsets: IndexSet) {
        for idx in offsets {
            let item = ipas[idx]
            try? FileManager.default.removeItem(at: item.url)
        }
        refreshIPAs()
    }
}

// MARK: - Account / Settings View
struct AccountView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var authCode = ""
    @State private var statusText: String?
    @State private var isLoading = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Apple Account")) {
                    TextField("Apple ID Email", text: $email)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    
                    SecureField("Password", text: $password)

                    TextField("2FA Code (Optional)", text: $authCode)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button(action: login) {
                        if isLoading {
                            HStack {
                                ProgressView()
                                Text("Logging in...")
                            }
                        } else {
                            Text("Log In")
                        }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isLoading)

                    Button("Revoke Credentials", role: .destructive) {
                        revoke()
                    }
                }

                if let st = statusText {
                    Section(header: Text("Console Output")) {
                        Text(st)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Account")
        }
    }

    private func login() {
        isLoading = true
        statusText = "Authenticating..."

        DispatchQueue.global(qos: .userInitiated).async {
            var args = ["auth", "login", "-e", email, "-p", password, "--non-interactive"]
            if !authCode.trimmingCharacters(in: .whitespaces).isEmpty {
                args += ["--auth-code", authCode.trimmingCharacters(in: .whitespaces)]
            }

            let res = CommandRunner.run(args: args)
            DispatchQueue.main.async {
                isLoading = false
                statusText = res.output
            }
        }
    }

    private func revoke() {
        statusText = "Revoking..."
        DispatchQueue.global(qos: .userInitiated).async {
            let res = CommandRunner.run(args: ["auth", "revoke"])
            DispatchQueue.main.async {
                statusText = res.output
            }
        }
    }
}

// MARK: - Share Sheet Helper
struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

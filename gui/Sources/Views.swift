import SwiftUI
import UIKit
import LinkPresentation

// MARK: - Main Tab View
public struct MainTabView: View {
    @StateObject private var searchVM = SearchViewModel()
    @StateObject private var downloadsVM = DownloadsViewModel()
    @StateObject private var accountVM = AccountViewModel()

    public init() {}

    public var body: some View {
        TabView {
            SearchView()
                .environmentObject(searchVM)
                .environmentObject(downloadsVM)
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }

            DownloadsView()
                .environmentObject(downloadsVM)
                .tabItem {
                    Label("Downloads", systemImage: "arrow.down.circle")
                }
                .badge(downloadsVM.activeDownloads.filter { !$0.status.isTerminal }.count)

            AccountView()
                .environmentObject(accountVM)
                .tabItem {
                    Label("Account", systemImage: "person.crop.circle")
                }
        }
        .accentColor(.blue)
    }
}

// MARK: - 1. Search View
public struct SearchView: View {
    @EnvironmentObject var searchVM: SearchViewModel
    @EnvironmentObject var downloadsVM: DownloadsViewModel

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Input Header
                searchHeader

                // Error Banner
                if let error = searchVM.errorMessage {
                    errorBanner(message: error)
                }

                // Content Area
                if searchVM.isLoading && searchVM.results.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Searching App Store...")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Spacer()
                    }
                } else if searchVM.results.isEmpty {
                    emptySearchState
                } else {
                    appList
                }
            }
            .navigationTitle("App Store Search")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $searchVM.selectedApp) { app in
                AppDetailView(app: app)
                    .environmentObject(searchVM)
                    .environmentObject(downloadsVM)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var searchHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search apps, bundle IDs...", text: $searchVM.query)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .submitLabel(.search)
                    .onSubmit {
                        searchVM.performSearch()
                    }

                if !searchVM.query.isEmpty {
                    Button(action: { searchVM.query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                if searchVM.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(10)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.top, 8)
        }
    }

    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.down.app")
                .font(.system(size: 60))
                .foregroundColor(.secondary.opacity(0.6))
            Text("Search Any App on iOS")
                .font(.headline)
            Text("Download IPAs directly on-device with TrollStore integration.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var appList: some View {
        List {
            ForEach(searchVM.results) { app in
                Button(action: {
                    searchVM.selectApp(app)
                }) {
                    AppRowView(app: app)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .listStyle(PlainListStyle())
    }

    private func errorBanner(message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.caption)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.15))
        .cornerRadius(8)
        .padding(.horizontal)
        .padding(.top, 4)
    }
}

// MARK: - App Row View
struct AppRowView: View {
    let app: AppItem

    var body: some View {
        HStack(spacing: 14) {
            // App Icon
            if let iconURL = app.iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        appPlaceholderIcon
                    }
                }
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.black.opacity(0.1), lineWidth: 0.5))
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
            } else {
                appPlaceholderIcon
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)

                if let seller = app.sellerName {
                    Text(seller)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    if let rating = app.averageUserRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.amberStar)
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(app.bundleIdentifier)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Price / Action Badge
            Text(app.displayPrice)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.blue)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.vertical, 6)
    }

    private var appPlaceholderIcon: some View {
        ZStack {
            Color(UIColor.secondarySystemBackground)
            Image(systemName: "app.fill")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
        }
        .frame(width: 58, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

// MARK: - 2. App Detail & Historical Versions View
public struct AppDetailView: View {
    let app: AppItem
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var searchVM: SearchViewModel
    @EnvironmentObject var downloadsVM: DownloadsViewModel

    @State private var isShowingVersionsInspector = false
    @State private var isPurchasing = false

    public var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header card
                    heroHeader

                    // Primary Actions
                    actionButtons

                    Divider()

                    // Release Notes / What's New
                    if let releaseNotes = app.releaseNotes, !releaseNotes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("What's New")
                                .font(.headline)
                            if let version = app.version {
                                Text("Version \(version)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Text(releaseNotes)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal)
                        Divider()
                    }

                    // Description
                    if let desc = app.description, !desc.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            Text(desc)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal)
                        Divider()
                    }

                    // Technical Specifications Card
                    technicalDetailsCard
                }
                .padding(.vertical)
            }
            .navigationBarTitle(app.name, displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .sheet(isPresented: $isShowingVersionsInspector) {
                HistoricalVersionsSheet(app: app)
                    .environmentObject(searchVM)
                    .environmentObject(downloadsVM)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var heroHeader: some View {
        HStack(spacing: 16) {
            if let iconURL = app.iconURL {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    default:
                        Image(systemName: "app.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 84, height: 84)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.title3.bold())
                    .lineLimit(2)

                if let seller = app.sellerName {
                    Text(seller)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 8) {
                    if let rating = app.averageUserRating {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.amberStar)
                            Text(String(format: "%.1f", rating))
                                .font(.caption.bold())
                        }
                    }

                    if let count = app.userRatingCount {
                        Text("(\(count) ratings)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // Download Latest Action
            Button(action: {
                downloadsVM.startDownload(app: app, versionId: nil, purchase: isPurchasing)
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.headline)
                    Text("Download Latest Version")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.blue)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Historical Versions Inspector Trigger
            Button(action: {
                isShowingVersionsInspector = true
                Task {
                    await searchVM.fetchHistoricalVersions(for: app)
                }
            }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.headline)
                    Text("Select Historical Version...")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(UIColor.secondarySystemBackground))
                .foregroundColor(.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Purchase License Toggle
            Toggle(isOn: $isPurchasing) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Acquire License (--purchase)")
                        .font(.subheadline.weight(.medium))
                    Text("Necessary if you have never acquired this free app on your Apple ID.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    private var technicalDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Information")
                .font(.headline)

            VStack(spacing: 10) {
                techRow(title: "Bundle ID", value: app.bundleIdentifier)
                techRow(title: "App Store ID", value: "\(app.id)")
                if let version = app.version {
                    techRow(title: "Current Version", value: version)
                }
                if let minOS = app.minimumOSVersion {
                    techRow(title: "Compatibility", value: "iOS \(minOS)+")
                }
                if let genres = app.genres, !genres.isEmpty {
                    techRow(title: "Category", value: genres.joined(separator: ", "))
                }
            }
            .padding(14)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal)
    }

    private func techRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Historical Versions Sheet
struct HistoricalVersionsSheet: View {
    let app: AppItem
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var searchVM: SearchViewModel
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    @State private var filterQuery = ""
    @State private var customVersionIdText = ""

    var filteredVersions: [Int64] {
        let q = filterQuery.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            return searchVM.historicalVersions
        }
        return searchVM.historicalVersions.filter { vId in
            if "\(vId)".contains(q) { return true }
            if let meta = searchVM.versionMetadataCache[vId],
               let ver = meta.displayVersion?.lowercased(),
               ver.contains(q) {
                return true
            }
            return false
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if searchVM.isLoadingVersions {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Querying App Store Version History...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Fetching all version identifiers with ipatool...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                } else if let error = searchVM.versionsError {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text("Could Not Fetch Versions")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        Button("Retry") {
                            Task {
                                await searchVM.fetchHistoricalVersions(for: app)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else {
                    // Filter bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search by Version (e.g. 2.4) or Version ID...", text: $filterQuery)
                            .textFieldStyle(PlainTextFieldStyle())
                        if !filterQuery.isEmpty {
                            Button(action: { filterQuery = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    // Versions List
                    List {
                        // Section 1: Direct Version ID Download
                        Section(header: Text("Direct Version ID Download")) {
                            HStack {
                                TextField("Enter Version ID (e.g. 864528192)", text: $customVersionIdText)
                                    .keyboardType(.numberPad)
                                    .font(.system(size: 14, design: .monospaced))

                                if !customVersionIdText.trimmingCharacters(in: .whitespaces).isEmpty {
                                    Button(action: {
                                        if let vId = Int64(customVersionIdText.trimmingCharacters(in: .whitespaces)) {
                                            downloadsVM.startDownload(app: app, versionId: vId)
                                            presentationMode.wrappedValue.dismiss()
                                        }
                                    }) {
                                        Text("Download")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(8)
                                    }
                                }
                            }
                        }

                        // Section 2: Historical Releases List
                        Section(header: HStack {
                            Text("\(searchVM.historicalVersions.count) Historical Releases")
                            Spacer()
                            Button(action: {
                                Task {
                                    await withTaskGroup(of: Void.self) { group in
                                        for vId in filteredVersions.prefix(10) {
                                            if searchVM.versionMetadataCache[vId]?.displayVersion == nil {
                                                group.addTask {
                                                    await searchVM.resolveVersionMetadata(for: app, versionId: vId)
                                                }
                                            }
                                        }
                                    }
                                }
                            }) {
                                HStack(spacing: 3) {
                                    Image(systemName: "bolt.fill")
                                    Text("Translate Top 10")
                                }
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.blue)
                            }
                        }) {
                            ForEach(filteredVersions, id: \.self) { versionId in
                                let meta = searchVM.versionMetadataCache[versionId]

                                Button(action: {
                                    downloadsVM.startDownload(app: app, versionId: versionId)
                                    presentationMode.wrappedValue.dismiss()
                                }) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            if let displayVer = meta?.displayVersion, !displayVer.isEmpty {
                                                HStack(spacing: 6) {
                                                    Text("v\(displayVer)")
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundColor(.primary)
                                                    Text("ID: \(versionId)")
                                                        .font(.system(size: 12, design: .monospaced))
                                                        .foregroundColor(.secondary)
                                                }
                                                if let date = meta?.releaseDate, !date.isEmpty {
                                                    Text("Released: \(date)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                } else {
                                                    Text("Tap to download this release")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            } else if meta?.isLoadingMetadata == true {
                                                HStack(spacing: 6) {
                                                    ProgressView().scaleEffect(0.7)
                                                    Text("Translating Version...")
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.secondary)
                                                }
                                                Text("Version ID: \(versionId)")
                                                    .font(.system(size: 12, design: .monospaced))
                                                    .foregroundColor(.secondary)
                                            } else {
                                                HStack(spacing: 8) {
                                                    Text("Version ID: \(versionId)")
                                                        .font(.system(size: 15, weight: .semibold, design: .monospaced))

                                                    Button(action: {
                                                        Task {
                                                            await searchVM.resolveVersionMetadata(for: app, versionId: versionId)
                                                        }
                                                    }) {
                                                        Text("Translate Version")
                                                            .font(.system(size: 11, weight: .medium))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.blue.opacity(0.12))
                                                            .foregroundColor(.blue)
                                                            .cornerRadius(5)
                                                    }
                                                    .buttonStyle(BorderlessButtonStyle())
                                                }
                                                Text("Tap row to download this release")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Image(systemName: "arrow.down.circle")
                                            .foregroundColor(.blue)
                                            .font(.title3)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                }
            }
            .navigationTitle("Historical Versions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - 3. Downloads View
public struct DownloadsView: View {
    @EnvironmentObject var downloadsVM: DownloadsViewModel
    @State private var selectedTab = 0 // 0 = Active, 1 = Storage, 2 = Live Logs
    @State private var ipaToDelete: DownloadedIPA? = nil
    @State private var isShowingDeleteConfirm = false
    @State private var ipaToShare: DownloadedIPA? = nil
    @State private var isShowingShareOptions = false

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Segmented Selector
                Picker("Downloads Mode", selection: $selectedTab) {
                    Text("Active (\(downloadsVM.activeDownloads.count))").tag(0)
                    Text("Storage (\(downloadsVM.downloadedIPAs.count))").tag(1)
                    Text("Console Logs").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                // Content Pages
                if selectedTab == 0 {
                    activeDownloadsSection
                } else if selectedTab == 1 {
                    storageSection
                } else {
                    LogConsoleView(logs: downloadsVM.liveLogs) {
                        downloadsVM.clearLogs()
                    }
                }
            }
            .navigationTitle("Downloads Manager")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $isShowingDeleteConfirm) {
                Alert(
                    title: Text("Delete IPA?"),
                    message: Text("Are you sure you want to permanently delete \(ipaToDelete?.fileName ?? "")?"),
                    primaryButton: .destructive(Text("Delete")) {
                        if let ipa = ipaToDelete {
                            downloadsVM.deleteIPA(ipa)
                        }
                    },
                    secondaryButton: .cancel()
                )
            }
            .actionSheet(isPresented: $isShowingShareOptions) {
                ActionSheet(
                    title: Text(ipaToShare?.fileName ?? "Share Package"),
                    message: Text("Select how to open or export this IPA package:"),
                    buttons: [
                        .default(Text("Open In... (All Apps / Filza / Files)")) {
                            if let ipa = ipaToShare {
                                ShareManager.shared.presentDocumentInteraction(for: ipa.url)
                            }
                        },
                        .default(Text("System Share Sheet (AirDrop / Share)")) {
                            if let ipa = ipaToShare {
                                ShareManager.shared.presentSystemShare(for: ipa.url)
                            }
                        },
                        .default(Text("Install via TrollStore")) {
                            if let ipa = ipaToShare {
                                downloadsVM.openInTrollStore(ipa)
                            }
                        },
                        .default(Text("Copy File Path")) {
                            if let ipa = ipaToShare {
                                UIPasteboard.general.string = ipa.url.path
                            }
                        },
                        .cancel()
                    ]
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var activeDownloadsSection: some View {
        VStack {
            if downloadsVM.activeDownloads.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 54))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Active Downloads")
                        .font(.headline)
                    Text("Search for an app and tap 'Download' to start.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(downloadsVM.activeDownloads) { task in
                        ActiveDownloadCard(task: task)
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        }
    }

    private var storageSection: some View {
        VStack(spacing: 0) {
            // Storage banner
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Downloaded IPAs")
                        .font(.headline)
                    Text("Total Storage Used: \(downloadsVM.storageUsedFormatted)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { downloadsVM.refreshDownloadedIPAs() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))

            if downloadsVM.downloadedIPAs.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "archivebox")
                        .font(.system(size: 54))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No Downloaded Packages")
                        .font(.headline)
                    Text("Completed IPAs will appear here with TrollStore quick actions.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Spacer()
                }
            } else {
                List {
                    ForEach(downloadsVM.downloadedIPAs) { ipa in
                        DownloadedIPARow(
                            ipa: ipa,
                            onInstall: {
                                downloadsVM.openInTrollStore(ipa)
                            },
                            onShare: {
                                ipaToShare = ipa
                                isShowingShareOptions = true
                            },
                            onDelete: {
                                ipaToDelete = ipa
                                isShowingDeleteConfirm = true
                            }
                        )
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
    }
}

// MARK: - Active Download Card
struct ActiveDownloadCard: View {
    let task: DownloadTask
    @State private var isShowingLogs = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let icon = task.app.iconURL {
                    AsyncImage(url: icon) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fit)
                        default:
                            Image(systemName: "app.fill").foregroundColor(.secondary)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.app.name)
                        .font(.system(size: 15, weight: .semibold))
                    Text(task.app.bundleIdentifier)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Spacer()

                statusBadge
            }

            // Progress Bar if downloading
            switch task.status {
            case .downloading(let progress, let speed):
                VStack(spacing: 4) {
                    ProgressView(value: progress)
                        .accentColor(.blue)
                    HStack {
                        Text("\(Int(progress * 100))%")
                            .font(.caption2.bold())
                        Spacer()
                        if !speed.isEmpty {
                            Text(speed)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            case .failed(let msg):
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            default:
                EmptyView()
            }

            // Drawer for recent logs
            DisclosureGroup(isExpanded: $isShowingLogs) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(task.logs.suffix(6)) { log in
                        Text("\(log.formattedTime) \(log.message)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Task Logs (\(task.logs.count))")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 6)
    }

    private var statusBadge: some View {
        Group {
            switch task.status {
            case .queued:
                Text("Queued")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            case .downloading:
                HStack(spacing: 4) {
                    ProgressView().scaleEffect(0.6)
                    Text("Downloading")
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.blue.opacity(0.2))
                .foregroundColor(.blue)
                .clipShape(Capsule())
            case .completed:
                Text("Completed")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.2))
                    .foregroundColor(.green)
                    .clipShape(Capsule())
            case .failed:
                Text("Failed")
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.2))
                    .foregroundColor(.red)
                    .clipShape(Capsule())
            }
        }
    }
}

// MARK: - Downloaded IPA Row
struct DownloadedIPARow: View {
    let ipa: DownloadedIPA
    let onInstall: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.zipper")
                .font(.system(size: 32))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(ipa.fileName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(ipa.formattedSize)
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(ipa.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Quick Actions
            HStack(spacing: 12) {
                // TrollStore Direct Install Button
                Button(action: onInstall) {
                    Image(systemName: "arrow.up.forward.app.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.green)
                }
                .buttonStyle(PlainButtonStyle())

                // Share Button
                Button(action: onShare) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                }
                .buttonStyle(PlainButtonStyle())

                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 18))
                        .foregroundColor(.red.opacity(0.8))
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button(action: onInstall) {
                Label("Install in TrollStore", systemImage: "arrow.up.forward.app")
            }
            Button(action: onShare) {
                Label("Share / Open In...", systemImage: "square.and.arrow.up")
            }
            Button(action: {
                UIPasteboard.general.string = ipa.url.path
            }) {
                Label("Copy File Path", systemImage: "doc.on.doc")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Package", systemImage: "trash")
            }
        }
    }
}

// MARK: - 4. Log Console View
public struct LogConsoleView: View {
    let logs: [LogEntry]
    let onClear: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            // Action bar
            HStack {
                Text("Console Stream")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)

                Spacer()

                Button("Copy All") {
                    let fullText = logs.map { "[\($0.formattedTime)] [\($0.level.rawValue)] \($0.message)" }.joined(separator: "\n")
                    UIPasteboard.general.string = fullText
                }
                .font(.caption)

                Button("Clear", action: onClear)
                    .font(.caption)
                    .foregroundColor(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))

            // Console Log Scroll
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(logs) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.formattedTime)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.gray)

                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(colorForLevel(entry.level))
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(10)
                }
                .background(Color.black)
                .onChange(of: logs.count) { _ in
                    if let last = logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .white
        case .warn: return .yellow
        case .error: return .red
        case .success: return .green
        }
    }
}

// MARK: - 5. Account & Settings View
public struct AccountView: View {
    @EnvironmentObject var accountVM: AccountViewModel
    @State private var isShowingLogoutConfirm = false

    public var body: some View {
        NavigationView {
            Form {
                // Section 1: Authentication State
                Section(header: Text("Apple ID Status")) {
                    if accountVM.isCheckingAuth {
                        HStack {
                            ProgressView()
                            Text("Verifying App Store session...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else if let session = accountVM.session {
                        authenticatedCard(session: session)
                    } else {
                        loginForm
                    }
                }

                // Section 2: Environment Diagnostics
                Section(header: Text("TrollStore & Binary Diagnostics")) {
                    HStack {
                        Text("ipatool Engine")
                        Spacer()
                        Text(accountVM.ipatoolVersion)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    ForEach(accountVM.binaryDiagnostics.sorted(by: { $0.key < $1.key }), id: \.key) { key, val in
                        HStack(alignment: .top) {
                            Text(key)
                                .font(.subheadline)
                            Spacer()
                            Text(val)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    Button("Re-run Diagnostics") {
                        accountVM.refreshDiagnostics()
                    }
                }

                // Section 3: App Information
                Section(header: Text("About IPATool GUI")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.8.1 (Native SwiftUI)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Runtime Target")
                        Spacer()
                        Text("iOS 15.0+ arm64")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Account & Settings")
            .navigationBarTitleDisplayMode(.inline)
            .alert(isPresented: $isShowingLogoutConfirm) {
                Alert(
                    title: Text("Revoke Credentials?"),
                    message: Text("This will clear your local App Store tokens from keychain."),
                    primaryButton: .destructive(Text("Sign Out")) {
                        Task { await accountVM.revoke() }
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func authenticatedCard(session: AccountSession) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 32))
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name ?? "Active App Store Account")
                        .font(.headline)
                    Text(session.email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Button(role: .destructive, action: { isShowingLogoutConfirm = true }) {
                HStack {
                    Spacer()
                    Text("Sign Out / Revoke Session")
                        .foregroundColor(.red)
                    Spacer()
                }
            }
            .padding(.top, 6)
        }
        .padding(.vertical, 4)
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in with Apple ID to search and download applications.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Apple ID Email", text: $accountVM.emailInput)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)

            SecureField("Password", text: $accountVM.passwordInput)
                .textContentType(.password)

            if accountVM.requires2FA {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Two-Factor Authentication Code")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                    TextField("6-digit Code", text: $accountVM.twoFactorCodeInput)
                        .keyboardType(.numberPad)
                }
            }

            if let err = accountVM.authErrorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            Button(action: {
                Task { await accountVM.login() }
            }) {
                HStack {
                    Spacer()
                    if accountVM.isAuthenticating {
                        ProgressView()
                            .padding(.trailing, 6)
                    }
                    Text(accountVM.requires2FA ? "Verify 2FA Code" : "Sign In")
                        .bold()
                    Spacer()
                }
            }
            .disabled(
                accountVM.isAuthenticating ||
                accountVM.emailInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                accountVM.passwordInput.isEmpty ||
                (accountVM.requires2FA && accountVM.twoFactorCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).count < 6)
            )
        }
    }
}

// MARK: - Safe IPA Share Item Source (Prevents LinkPresentation IPA inspection crash)
public final class IPAShareItemSource: NSObject, UIActivityItemSource {
    public let fileURL: URL
    public let fileName: String

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.fileName = fileURL.lastPathComponent
        super.init()
    }

    public func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        return fileURL
    }

    public func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        return fileURL
    }

    public func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return fileName
    }

    public func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = fileName
        metadata.originalURL = fileURL
        return metadata
    }
}

// MARK: - Native Document Interaction & Share Manager
@MainActor
public final class ShareManager {
    public static let shared = ShareManager()

    private var activeDocController: UIDocumentInteractionController?

    // 1. UIDocumentInteractionController ("Open in..." Menu)
    // 100% crash-proof in TrollStore/jailbreak environments because it bypasses SharingUI container requirements.
    public func presentDocumentInteraction(for url: URL, from sourceView: UIView? = nil) {
        guard let topVC = Self.getTopViewController() else { return }

        let docController = UIDocumentInteractionController(url: url)
        self.activeDocController = docController

        let targetView = sourceView ?? topVC.view ?? UIView()
        let rect = CGRect(
            x: targetView.bounds.midX - 1,
            y: targetView.bounds.midY - 1,
            width: 2,
            height: 2
        )

        let success = docController.presentOptionsMenu(from: rect, in: targetView, animated: true)
        if !success {
            docController.presentOpenInMenu(from: rect, in: targetView, animated: true)
        }
    }

    // 2. UIActivityViewController (System Share Sheet)
    // Guarded with IPAShareItemSource and non-zero iPad popover bounds
    public func presentSystemShare(for url: URL, from sourceView: UIView? = nil) {
        guard let topVC = Self.getTopViewController() else { return }

        let itemSource = IPAShareItemSource(fileURL: url)
        let activityVC = UIActivityViewController(
            activityItems: [itemSource],
            applicationActivities: nil
        )

        let targetView = sourceView ?? topVC.view ?? UIView()
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = targetView
            popover.sourceRect = CGRect(
                x: targetView.bounds.midX - 1,
                y: targetView.bounds.midY - 1,
                width: 2,
                height: 2
            )
            popover.permittedArrowDirections = .any
        }

        var presenter = topVC
        while let presented = presenter.presentedViewController, !presented.isBeingDismissed {
            presenter = presented
        }

        presenter.present(activityVC, animated: true)
    }

    // Top view controller discovery
    public static func getTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let activeScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first
        
        let validWindows = activeScene?.windows.filter { window in
            let desc = String(describing: type(of: window))
            return !desc.contains("TextEffects") && !desc.contains("RemoteKeyboard")
        } ?? []

        guard let window = validWindows.first(where: { $0.isKeyWindow }) ?? validWindows.first ?? activeScene?.windows.first,
              let rootVC = window.rootViewController else {
            return nil
        }
        return topViewController(from: rootVC)
    }

    private static func topViewController(from base: UIViewController?) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return topViewController(from: nav.visibleViewController ?? nav.topViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController, !presented.isBeingDismissed {
            return topViewController(from: presented)
        }
        return base
    }
}

// MARK: - Legacy Share Presenter Adapter
@MainActor
public enum SharePresenter {
    public static func present(items: [Any]) {
        if let firstURL = items.first(where: { $0 is URL }) as? URL {
            ShareManager.shared.presentSystemShare(for: firstURL)
        }
    }
}

public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public init(activityItems: [Any]) {
        self.activityItems = activityItems
    }
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let items: [Any] = activityItems.compactMap { item in
            if let url = item as? URL {
                return IPAShareItemSource(fileURL: url)
            }
            return item
        }
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX - 1, y: UIScreen.main.bounds.midY - 1, width: 2, height: 2)
            popover.permittedArrowDirections = .any
        }
        return controller
    }
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Extensions
extension Color {
    static let amberStar = Color(red: 255/255, green: 179/255, blue: 0/255)
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

import Foundation

struct SearchResult: Codable {
    var apps: [AppItem]?
    var count: Int?
}

struct AppItem: Identifiable, Codable, Hashable {
    var id: Int64
    var bundleIdentifier: String
    var name: String
    var version: String?
    var price: Double?
}

struct VersionListResult: Codable {
    var externalVersionIdentifiers: [Int64]?
    var bundleID: String?
    var success: Bool?
}

struct DownloadedIPA: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let sizeString: String
}

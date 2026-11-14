import Foundation

// MARK: - App Store App Item
public struct AppItem: Identifiable, Codable, Hashable {
    public let id: Int64
    public let bundleIdentifier: String
    public let name: String
    public var version: String?
    public var price: Double?
    public var formattedPrice: String?
    public var sellerName: String?
    public var iconURL: URL?
    public var averageUserRating: Double?
    public var userRatingCount: Int?
    public var description: String?
    public var genres: [String]?
    public var minimumOSVersion: String?
    public var releaseNotes: String?

    public init(
        id: Int64,
        bundleIdentifier: String,
        name: String,
        version: String? = nil,
        price: Double? = nil,
        formattedPrice: String? = nil,
        sellerName: String? = nil,
        iconURL: URL? = nil,
        averageUserRating: Double? = nil,
        userRatingCount: Int? = nil,
        description: String? = nil,
        genres: [String]? = nil,
        minimumOSVersion: String? = nil,
        releaseNotes: String? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.price = price
        self.formattedPrice = formattedPrice
        self.sellerName = sellerName
        self.iconURL = iconURL
        self.averageUserRating = averageUserRating
        self.userRatingCount = userRatingCount
        self.description = description
        self.genres = genres
        self.minimumOSVersion = minimumOSVersion
        self.releaseNotes = releaseNotes
    }

    enum CodingKeys: String, CodingKey {
        case id = "trackId"
        case altId = "id"
        case bundleIdentifier = "bundleId"
        case altBundleId = "bundleIdentifier"
        case name = "trackName"
        case altName = "name"
        case version
        case price
        case formattedPrice
        case sellerName = "artistName"
        case altSellerName = "sellerName"
        case artworkUrl512
        case artworkUrl100
        case artworkUrl60
        case averageUserRating
        case userRatingCount
        case description
        case genres
        case minimumOSVersion = "minimumOsVersion"
        case releaseNotes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode trackId / id
        if let trackId = try? container.decode(Int64.self, forKey: .id) {
            self.id = trackId
        } else if let altId = try? container.decode(Int64.self, forKey: .altId) {
            self.id = altId
        } else if let idStr = try? container.decode(String.self, forKey: .id), let idInt = Int64(idStr) {
            self.id = idInt
        } else {
            self.id = 0
        }

        // Decode bundleIdentifier / bundleId
        if let bId = try? container.decode(String.self, forKey: .bundleIdentifier) {
            self.bundleIdentifier = bId
        } else if let altBId = try? container.decode(String.self, forKey: .altBundleId) {
            self.bundleIdentifier = altBId
        } else {
            self.bundleIdentifier = ""
        }

        // Decode trackName / name
        if let tName = try? container.decode(String.self, forKey: .name) {
            self.name = tName
        } else if let altName = try? container.decode(String.self, forKey: .altName) {
            self.name = altName
        } else {
            self.name = "Unknown App"
        }

        self.version = try? container.decode(String.self, forKey: .version)
        self.price = try? container.decode(Double.self, forKey: .price)
        self.formattedPrice = try? container.decode(String.self, forKey: .formattedPrice)

        if let artist = try? container.decode(String.self, forKey: .sellerName) {
            self.sellerName = artist
        } else {
            self.sellerName = try? container.decode(String.self, forKey: .altSellerName)
        }

        // Artwork URL parsing (prefer 512, then 100, then 60)
        if let art512 = try? container.decode(String.self, forKey: .artworkUrl512), let u = URL(string: art512) {
            self.iconURL = u
        } else if let art100 = try? container.decode(String.self, forKey: .artworkUrl100), let u = URL(string: art100) {
            self.iconURL = u
        } else if let art60 = try? container.decode(String.self, forKey: .artworkUrl60), let u = URL(string: art60) {
            self.iconURL = u
        } else {
            self.iconURL = nil
        }

        self.averageUserRating = try? container.decode(Double.self, forKey: .averageUserRating)
        self.userRatingCount = try? container.decode(Int.self, forKey: .userRatingCount)
        self.description = try? container.decode(String.self, forKey: .description)
        self.genres = try? container.decode([String].self, forKey: .genres)
        self.minimumOSVersion = try? container.decode(String.self, forKey: .minimumOSVersion)
        self.releaseNotes = try? container.decode(String.self, forKey: .releaseNotes)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(bundleIdentifier, forKey: .bundleIdentifier)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encodeIfPresent(formattedPrice, forKey: .formattedPrice)
        try container.encodeIfPresent(sellerName, forKey: .sellerName)
        try container.encodeIfPresent(iconURL?.absoluteString, forKey: .artworkUrl512)
        try container.encodeIfPresent(averageUserRating, forKey: .averageUserRating)
        try container.encodeIfPresent(userRatingCount, forKey: .userRatingCount)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(genres, forKey: .genres)
        try container.encodeIfPresent(minimumOSVersion, forKey: .minimumOSVersion)
        try container.encodeIfPresent(releaseNotes, forKey: .releaseNotes)
    }

    public var displayPrice: String {
        if let formatted = formattedPrice {
            return formatted
        }
        if let p = price {
            return p == 0.0 ? "GET" : String(format: "$%.2f", p)
        }
        return "GET"
    }

    public var ratingStarsText: String {
        guard let rating = averageUserRating else { return "No Ratings" }
        return String(format: "%.1f ★", rating)
    }
}

// MARK: - Search Container Decoders
public struct IPAToolSearchResult: Codable {
    public let count: Int?
    public let apps: [AppItem]?
}

public struct iTunesSearchResponse: Codable {
    public let resultCount: Int
    public let results: [AppItem]
}

// MARK: - Version List Result
public struct VersionListResult: Codable {
    public let externalVersionIdentifiers: [Int64]?
    public let bundleID: String?
    public let success: Bool?

    enum CodingKeys: String, CodingKey {
        case externalVersionIdentifiers
        case bundleID
        case success
    }
}

// MARK: - Account Session
public struct AccountSession: Codable, Equatable {
    public let email: String
    public let name: String?
    public let appleID: String?
    public let storefront: String?

    public init(email: String, name: String? = nil, appleID: String? = nil, storefront: String? = nil) {
        self.email = email
        self.name = name
        self.appleID = appleID
        self.storefront = storefront
    }
}

// MARK: - Download Task & Status
public enum DownloadStatus: Equatable {
    case queued
    case downloading(progress: Double, speed: String)
    case completed(outputURL: URL)
    case failed(message: String)

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed: return true
        default: return false
        }
    }
}

public struct DownloadTask: Identifiable {
    public let id: UUID
    public let app: AppItem
    public let versionId: Int64?
    public var status: DownloadStatus
    public var logs: [LogEntry]
    public let startDate: Date

    public init(app: AppItem, versionId: Int64? = nil) {
        self.id = UUID()
        self.app = app
        self.versionId = versionId
        self.status = .queued
        self.logs = []
        self.startDate = Date()
    }
}

// MARK: - Downloaded IPA File Info
public struct DownloadedIPA: Identifiable, Hashable {
    public var id: String { url.path }
    public let url: URL
    public let fileName: String
    public let bundleIdentifier: String?
    public let version: String?
    public let fileSizeBytes: Int64
    public let creationDate: Date

    public init(url: URL, bundleIdentifier: String? = nil, version: String? = nil) {
        self.url = url
        self.fileName = url.lastPathComponent
        self.bundleIdentifier = bundleIdentifier
        self.version = version

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes?[.size] as? Int64 ?? 0
        let date = attributes?[.creationDate] as? Date ?? Date()

        self.fileSizeBytes = size
        self.creationDate = date
    }

    public var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSizeBytes)
    }

    public var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: creationDate)
    }
}

// MARK: - Log Entry
public enum LogLevel: String, Codable {
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case success = "SUCCESS"
}

public struct LogEntry: Identifiable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let message: String
    public let level: LogLevel

    public init(message: String, level: LogLevel = .info) {
        self.id = UUID()
        self.timestamp = Date()
        self.message = message
        self.level = level
    }

    public var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}

// MARK: - CLI Execution Result
public struct CLIExecutionResult {
    public let output: String
    public let exitCode: Int32
    public let duration: TimeInterval

    public var isSuccess: Bool {
        return exitCode == 0
    }
}

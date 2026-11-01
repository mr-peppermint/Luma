import Foundation

enum WallpaperOrigin: String, Codable, CaseIterable {
    case local
    case steamWorkshop
}

/// Provenance of a Workshop-imported video, kept so repeat scans can detect duplicates
/// and so the original Steam files are never touched.
struct WorkshopProvenance: Codable, Hashable {
    var workshopID: String
    var sourceFolderPath: String
    var sourceFileFingerprint: String
}

struct VideoWallpaper: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var fileURL: URL
    var thumbnailURL: URL?
    var origin: WallpaperOrigin
    var durationSeconds: Double?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var isFavorite: Bool
    var collectionIDs: Set<UUID>
    var dateAdded: Date
    var workshopInfo: WorkshopProvenance?

    init(
        id: UUID = UUID(),
        title: String,
        fileURL: URL,
        thumbnailURL: URL? = nil,
        origin: WallpaperOrigin = .local,
        durationSeconds: Double? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        isFavorite: Bool = false,
        collectionIDs: Set<UUID> = [],
        dateAdded: Date = .now,
        workshopInfo: WorkshopProvenance? = nil
    ) {
        self.id = id
        self.title = title
        self.fileURL = fileURL
        self.thumbnailURL = thumbnailURL
        self.origin = origin
        self.durationSeconds = durationSeconds
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.isFavorite = isFavorite
        self.collectionIDs = collectionIDs
        self.dateAdded = dateAdded
        self.workshopInfo = workshopInfo
    }
}

struct WallpaperCollection: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var dateCreated: Date = .now
}

enum WallpaperDestination: String, Codable, CaseIterable, Identifiable {
    case desktop
    case lockScreen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .desktop: "Desktop"
        case .lockScreen: "Lock Screen (Experimental)"
        }
    }
}

/// A stable per-display slot. `displayID` is the display's persistent identifier
/// (from `CGDisplay` UUID), never its index in `NSScreen.screens`, so assignments
/// survive reordering when displays are connected/disconnected.
struct DisplayAssignment: Codable, Hashable, Identifiable {
    var displayID: String
    var wallpaperID: UUID?
    var destinations: Set<WallpaperDestination>

    var id: String { displayID }
}

enum FitMode: String, Codable, CaseIterable, Identifiable {
    case fit
    case fill

    var id: String { rawValue }
    var title: String { self == .fit ? "Fit" : "Fill" }
}

enum FrameRateCap: Int, Codable, CaseIterable, Identifiable {
    case uncapped = 0
    case fps15 = 15
    case fps30 = 30
    case fps60 = 60

    var id: Int { rawValue }
    var title: String { self == .uncapped ? "Uncapped" : "\(rawValue) fps" }
}

struct PlaybackSettings: Codable, Hashable {
    var isMuted: Bool = true
    var fitMode: FitMode = .fill
    var pauseWhenLocked: Bool = true
    var pauseOnBattery: Bool = false
    var frameRateCap: FrameRateCap = .fps30
    var lockScreenExperimentEnabled: Bool = false
}

enum RotationScope: String, Codable, CaseIterable, Identifiable {
    case off
    case favorites
    case collection
    case allWallpapers

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .favorites: "Favorites"
        case .collection: "A Collection"
        case .allWallpapers: "All Wallpapers"
        }
    }
}

struct RotationSettings: Codable, Hashable {
    var scope: RotationScope = .off
    var collectionID: UUID?
    var intervalMinutes: Double = 30
    var syncAcrossDisplays: Bool = true
}

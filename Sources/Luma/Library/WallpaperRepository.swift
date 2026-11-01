import Foundation

protocol WallpaperRepository: Sendable {
    func all() async throws -> [VideoWallpaper]
    func add(_ wallpaper: VideoWallpaper) async throws
    func update(_ wallpaper: VideoWallpaper) async throws
    func remove(id: UUID) async throws
    func fingerprintExists(_ fingerprint: String) async throws -> Bool

    func allCollections() async throws -> [WallpaperCollection]
    func addCollection(_ collection: WallpaperCollection) async throws
    func removeCollection(id: UUID) async throws

    func allDisplayAssignments() async throws -> [DisplayAssignment]
    func setDisplayAssignment(_ assignment: DisplayAssignment) async throws

    func loadPlaybackSettings() async throws -> PlaybackSettings
    func savePlaybackSettings(_ settings: PlaybackSettings) async throws

    func loadRotationSettings() async throws -> RotationSettings
    func saveRotationSettings(_ settings: RotationSettings) async throws
}

/// Versioned on-disk document for all app state. A JSON file is sufficient here because
/// the model is small, non-relational, and never queried — SwiftData's query/relationship
/// machinery would add complexity without benefit for this app's footprint. Large binary
/// assets (videos, thumbnails) never live in this document; only their file URLs do.
private struct PersistedState: Codable {
    var schemaVersion: Int = 1
    var wallpapers: [VideoWallpaper] = []
    var collections: [WallpaperCollection] = []
    var displayAssignments: [DisplayAssignment] = []
    var playbackSettings: PlaybackSettings = PlaybackSettings()
    var rotationSettings: RotationSettings = RotationSettings()
}

actor JSONWallpaperRepository: WallpaperRepository {
    private let indexURL: URL
    private var state: PersistedState?

    init(indexURL: URL? = nil) {
        if let indexURL {
            self.indexURL = indexURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.indexURL = appSupport.appendingPathComponent("Luma/library.json")
        }
    }

    func all() async throws -> [VideoWallpaper] {
        try loadIfNeeded()
        return state?.wallpapers ?? []
    }

    func add(_ wallpaper: VideoWallpaper) async throws {
        try loadIfNeeded()
        guard state?.wallpapers.contains(where: { $0.id == wallpaper.id }) == false else { return }
        state?.wallpapers.append(wallpaper)
        try persist()
    }

    func update(_ wallpaper: VideoWallpaper) async throws {
        try loadIfNeeded()
        guard let index = state?.wallpapers.firstIndex(where: { $0.id == wallpaper.id }) else { return }
        state?.wallpapers[index] = wallpaper
        try persist()
    }

    func remove(id: UUID) async throws {
        try loadIfNeeded()
        state?.wallpapers.removeAll { $0.id == id }
        for assignment in state?.displayAssignments ?? [] where assignment.wallpaperID == id {
            var cleared = assignment
            cleared.wallpaperID = nil
            state?.displayAssignments.removeAll { $0.displayID == assignment.displayID }
            state?.displayAssignments.append(cleared)
        }
        try persist()
    }

    func fingerprintExists(_ fingerprint: String) async throws -> Bool {
        try loadIfNeeded()
        return state?.wallpapers.contains { $0.workshopInfo?.sourceFileFingerprint == fingerprint } ?? false
    }

    func allCollections() async throws -> [WallpaperCollection] {
        try loadIfNeeded()
        return state?.collections ?? []
    }

    func addCollection(_ collection: WallpaperCollection) async throws {
        try loadIfNeeded()
        state?.collections.append(collection)
        try persist()
    }

    func removeCollection(id: UUID) async throws {
        try loadIfNeeded()
        state?.collections.removeAll { $0.id == id }
        for index in (state?.wallpapers.indices ?? 0..<0) {
            state?.wallpapers[index].collectionIDs.remove(id)
        }
        try persist()
    }

    func allDisplayAssignments() async throws -> [DisplayAssignment] {
        try loadIfNeeded()
        return state?.displayAssignments ?? []
    }

    func setDisplayAssignment(_ assignment: DisplayAssignment) async throws {
        try loadIfNeeded()
        state?.displayAssignments.removeAll { $0.displayID == assignment.displayID }
        state?.displayAssignments.append(assignment)
        try persist()
    }

    func loadPlaybackSettings() async throws -> PlaybackSettings {
        try loadIfNeeded()
        return state?.playbackSettings ?? PlaybackSettings()
    }

    func savePlaybackSettings(_ settings: PlaybackSettings) async throws {
        try loadIfNeeded()
        state?.playbackSettings = settings
        try persist()
    }

    func loadRotationSettings() async throws -> RotationSettings {
        try loadIfNeeded()
        return state?.rotationSettings ?? RotationSettings()
    }

    func saveRotationSettings(_ settings: RotationSettings) async throws {
        try loadIfNeeded()
        state?.rotationSettings = settings
        try persist()
    }

    private func loadIfNeeded() throws {
        guard state == nil else { return }
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            state = PersistedState()
            return
        }
        let data = try Data(contentsOf: indexURL)
        state = try JSONDecoder().decode(PersistedState.self, from: data)
    }

    private func persist() throws {
        let directory = indexURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state ?? PersistedState()).write(to: indexURL, options: .atomic)
    }
}

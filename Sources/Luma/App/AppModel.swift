import AppKit
import Combine
import SwiftUI

enum LibrarySection: Hashable {
    case all, favorites, recent, local, workshop

    var title: String {
        switch self {
        case .all: "All Wallpapers"
        case .favorites: "Favorites"
        case .recent: "Recently Added"
        case .local: "My Videos"
        case .workshop: "Steam Workshop"
        }
    }
}

/// Central app state: the wallpaper library, collections, and per-display assignments.
/// Owns persistence (through `AppEnvironment.repository`) and keeps the desktop coordinator
/// in sync whenever any of that state changes. Playback settings and rotation settings live
/// on `AppEnvironment.playbackPolicy` / `.rotationScheduler` directly — this type only reacts
/// to them so the desktop coordinator always reflects the latest values.
@MainActor
final class AppModel: ObservableObject {
    @Published var wallpapers: [VideoWallpaper] = []
    @Published var collections: [WallpaperCollection] = []
    @Published var displayAssignments: [DisplayAssignment] = []
    @Published var availableDisplays: [DisplayInfo] = []

    @Published var searchText = ""
    @Published var selectedWallpaperID: UUID?
    @Published var importError: String?
    @Published var isImporting = false
    @Published var isShowingImporter = false
    @Published var selectedSection: LibrarySection = .all
    @Published var selectedCollectionID: UUID?
    @Published private(set) var isBootstrapped = false

    let env: AppEnvironment
    private var cancellables: Set<AnyCancellable> = []

    init(env: AppEnvironment) {
        self.env = env
        availableDisplays = DisplayInfo.current()
        observeScreenChanges()
        observeSettingsForRotationAndCoordinator()
        Task { await bootstrap() }
    }

    var visibleWallpapers: [VideoWallpaper] {
        let base: [VideoWallpaper]
        switch selectedSection {
        case .all: base = wallpapers
        case .favorites: base = wallpapers.filter(\.isFavorite)
        case .recent: base = wallpapers.sorted { $0.dateAdded > $1.dateAdded }
        case .local: base = wallpapers.filter { $0.origin == .local }
        case .workshop: base = wallpapers.filter { $0.origin == .steamWorkshop }
        }
        let collectionFiltered = selectedCollectionID.map { id in base.filter { $0.collectionIDs.contains(id) } } ?? base
        guard !searchText.isEmpty else { return collectionFiltered }
        return collectionFiltered.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    // MARK: Bootstrap

    private func bootstrap() async {
        await reloadWallpapers()
        await reloadCollections()
        await reloadDisplayAssignments()
        await loadPersistedSettings()
        reconcileAssignmentsWithAvailableDisplays()
        isBootstrapped = true
        resumeDesktopPlaybackIfAssigned()
    }

    private func loadPersistedSettings() async {
        do {
            env.playbackPolicy.settings = try await env.repository.loadPlaybackSettings()
            env.rotationScheduler.settings = try await env.repository.loadRotationSettings()
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: Library

    func reloadWallpapers() async {
        do { wallpapers = try await env.repository.all() }
        catch { importError = error.localizedDescription }
    }

    func importVideos(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        for url in urls {
            do {
                let wallpaper = try await env.importer.importVideo(from: url)
                try await env.repository.add(wallpaper)
            } catch {
                importError = "\(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        await reloadWallpapers()
    }

    func toggleFavorite(_ wallpaper: VideoWallpaper) {
        var updated = wallpaper
        updated.isFavorite.toggle()
        Task {
            try? await env.repository.update(updated)
            await reloadWallpapers()
        }
    }

    func removeWallpaper(_ wallpaper: VideoWallpaper) {
        Task {
            try? await env.repository.remove(id: wallpaper.id)
            await reloadWallpapers()
            await reloadDisplayAssignments()
        }
    }

    func addWallpaper(_ wallpaper: VideoWallpaper, replacingDuplicateFingerprint: Bool = false) async {
        try? await env.repository.add(wallpaper)
        await reloadWallpapers()
    }

    // MARK: Collections

    func reloadCollections() async {
        do { collections = try await env.repository.allCollections() }
        catch { importError = error.localizedDescription }
    }

    func createCollection(named name: String) {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            try? await env.repository.addCollection(WallpaperCollection(name: name))
            await reloadCollections()
        }
    }

    func deleteCollection(_ collection: WallpaperCollection) {
        Task {
            try? await env.repository.removeCollection(id: collection.id)
            if selectedCollectionID == collection.id { selectedCollectionID = nil }
            await reloadCollections()
            await reloadWallpapers()
        }
    }

    func toggleMembership(of wallpaper: VideoWallpaper, in collection: WallpaperCollection) {
        var updated = wallpaper
        if updated.collectionIDs.contains(collection.id) {
            updated.collectionIDs.remove(collection.id)
        } else {
            updated.collectionIDs.insert(collection.id)
        }
        Task {
            try? await env.repository.update(updated)
            await reloadWallpapers()
        }
    }

    // MARK: Display assignments

    func reloadDisplayAssignments() async {
        do { displayAssignments = try await env.repository.allDisplayAssignments() }
        catch { importError = error.localizedDescription }
    }

    private func observeScreenChanges() {
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.availableDisplays = DisplayInfo.current()
                self?.reconcileAssignmentsWithAvailableDisplays()
            }
            .store(in: &cancellables)
    }

    /// Ensures every connected display has an assignment record (even an empty one) so the
    /// Displays UI always lists every screen, and preserves assignments for displays that
    /// are temporarily disconnected rather than deleting them.
    private func reconcileAssignmentsWithAvailableDisplays() {
        for display in availableDisplays where !displayAssignments.contains(where: { $0.displayID == display.id }) {
            let blank = DisplayAssignment(displayID: display.id, wallpaperID: nil, destinations: [])
            displayAssignments.append(blank)
            Task { try? await env.repository.setDisplayAssignment(blank) }
        }
    }

    func assignment(for display: DisplayInfo) -> DisplayAssignment {
        displayAssignments.first(where: { $0.displayID == display.id })
            ?? DisplayAssignment(displayID: display.id, wallpaperID: nil, destinations: [])
    }

    func updateAssignment(
        for display: DisplayInfo,
        wallpaperID: UUID?,
        destinations: Set<WallpaperDestination>
    ) {
        let assignment = DisplayAssignment(displayID: display.id, wallpaperID: wallpaperID, destinations: destinations)
        displayAssignments.removeAll { $0.displayID == display.id }
        displayAssignments.append(assignment)
        Task { try? await env.repository.setDisplayAssignment(assignment) }
        pushAssignmentsToCoordinatorIfRunning()
    }

    /// Applies one wallpaper to every connected display at once, keeping each display's
    /// existing destination choice (or defaulting to Desktop if none was set).
    func assignWallpaperToAllDisplays(_ wallpaper: VideoWallpaper) {
        for display in availableDisplays {
            let existing = assignment(for: display)
            let destinations = existing.destinations.isEmpty ? [WallpaperDestination.desktop] : existing.destinations
            updateAssignment(for: display, wallpaperID: wallpaper.id, destinations: destinations)
        }
    }

    // MARK: Desktop playback

    func resumeDesktopPlaybackIfAssigned() {
        let hasDesktopAssignment = displayAssignments.contains {
            $0.destinations.contains(.desktop) && $0.wallpaperID != nil
        }
        guard hasDesktopAssignment else { return }
        startDesktopPlayback()
    }

    func startDesktopPlayback() {
        env.desktopCoordinator.start(assignments: displayAssignments, wallpapers: wallpapers, policy: env.playbackPolicy)
    }

    func stopDesktopPlayback() {
        env.desktopCoordinator.stop()
    }

    private func pushAssignmentsToCoordinatorIfRunning() {
        guard env.desktopCoordinator.isRunning else { return }
        env.desktopCoordinator.updateAssignments(displayAssignments, wallpapers: wallpapers)
    }

    private func observeSettingsForRotationAndCoordinator() {
        env.playbackPolicy.$settings
            .dropFirst()
            .sink { [weak self] settings in
                Task { try? await self?.env.repository.savePlaybackSettings(settings) }
            }
            .store(in: &cancellables)

        env.rotationScheduler.$settings
            .dropFirst()
            .sink { [weak self] settings in
                Task { try? await self?.env.repository.saveRotationSettings(settings) }
            }
            .store(in: &cancellables)

        env.rotationScheduler.wallpaperPoolProvider = { [weak self] in self?.wallpapers ?? [] }
        env.rotationScheduler.currentAssignmentsProvider = { [weak self] in self?.displayAssignments ?? [] }
        env.rotationScheduler.onRotate = { [weak self] updated in
            guard let self else { return }
            displayAssignments = updated
            for assignment in updated {
                Task { try? await self.env.repository.setDisplayAssignment(assignment) }
            }
            pushAssignmentsToCoordinatorIfRunning()
        }
    }
}

import Foundation

/// Cycles the wallpaper assigned to each display on a timer. Pure scheduling logic — it
/// reads the current library/assignments through closures and hands back the assignments
/// it wants applied; the caller persists and forwards them to the desktop coordinator.
@MainActor
final class RotationScheduler: ObservableObject {
    @Published var settings: RotationSettings {
        didSet { restartTimer() }
    }

    var wallpaperPoolProvider: () -> [VideoWallpaper] = { [] }
    var currentAssignmentsProvider: () -> [DisplayAssignment] = { [] }
    var onRotate: ([DisplayAssignment]) -> Void = { _ in }

    private var timer: Timer?
    private var sharedIndex = 0
    private var perDisplayIndex: [String: Int] = [:]

    init(settings: RotationSettings) {
        self.settings = settings
        restartTimer()
    }

    deinit {
        timer?.invalidate()
    }

    func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard settings.scope != .off, settings.intervalMinutes > 0 else { return }
        let interval = max(60, settings.intervalMinutes * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rotateNow() }
        }
    }

    func rotateNow() {
        guard settings.scope != .off else { return }
        let pool = pooledWallpapers()
        guard !pool.isEmpty else { return }
        let assignments = currentAssignmentsProvider()
        guard !assignments.isEmpty else { return }

        var updated: [DisplayAssignment] = []
        if settings.syncAcrossDisplays {
            sharedIndex = (sharedIndex + 1) % pool.count
            let next = pool[sharedIndex]
            updated = assignments.map { assignment in
                var copy = assignment
                copy.wallpaperID = next.id
                return copy
            }
        } else {
            updated = assignments.map { assignment in
                var copy = assignment
                var index = perDisplayIndex[assignment.displayID] ?? Int.random(in: 0..<pool.count)
                index = (index + 1) % pool.count
                perDisplayIndex[assignment.displayID] = index
                copy.wallpaperID = pool[index].id
                return copy
            }
        }
        onRotate(updated)
    }

    private func pooledWallpapers() -> [VideoWallpaper] {
        let all = wallpaperPoolProvider()
        switch settings.scope {
        case .off:
            return []
        case .favorites:
            return all.filter(\.isFavorite)
        case .collection:
            guard let collectionID = settings.collectionID else { return [] }
            return all.filter { $0.collectionIDs.contains(collectionID) }
        case .allWallpapers:
            return all
        }
    }
}

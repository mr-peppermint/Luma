import Foundation

/// Wires up every service the app needs and owns their lifetime. Created once at launch and
/// handed down via `@EnvironmentObject`/initializers; nothing in `UI/` constructs a service
/// directly.
@MainActor
final class AppEnvironment: ObservableObject {
    let repository: any WallpaperRepository
    let importer = VideoImportService()
    let steamLocator = SteamLibraryLocator()
    let workshopScanner = WorkshopScanner()
    let workshopImporter = WorkshopImporter()

    let powerMonitor: PowerMonitor
    let playbackPolicy: PlaybackPolicy
    let desktopCoordinator = DesktopWallpaperCoordinator()
    let rotationScheduler: RotationScheduler

    init(repository: any WallpaperRepository = JSONWallpaperRepository()) {
        self.repository = repository
        let powerMonitor = PowerMonitor()
        self.powerMonitor = powerMonitor
        self.playbackPolicy = PlaybackPolicy(settings: PlaybackSettings(), powerMonitor: powerMonitor)
        self.rotationScheduler = RotationScheduler(settings: RotationSettings())
    }
}

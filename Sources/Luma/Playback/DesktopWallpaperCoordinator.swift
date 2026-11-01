import AppKit
import AVFoundation
import Combine

/// One borderless, click-through, all-Spaces window per display, each playing its assigned
/// video. Windows sit one level below the desktop-icon layer so Finder icons stay on top and
/// usable, and one level above the ordinary desktop-picture layer.
///
/// Known limits, surfaced in the UI rather than hidden: macOS has no public API to set a
/// video as the actual desktop picture, so this is an app-owned window technique. Window
/// ordering relative to Finder icons, visibility across Spaces, and behavior around
/// fullscreen apps, sleep/wake, and display reconfiguration can vary across macOS releases.
/// If Luma quits or crashes, the window technique stops with it — the system reverts to
/// whatever was last set via `NSWorkspace.setDesktopImageURL`, which is why this coordinator
/// also sets a still poster frame there before it starts animating.
@MainActor
final class DesktopWallpaperCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var activeDisplayCount = 0

    private var windows: [String: NSWindow] = [:]
    private var renderers: [String: DesktopVideoView] = [:]
    private var players: [String: AVPlayer] = [:]
    private let ciContext = CIContext()
    private var screenChangeObserver: NSObjectProtocol?

    private var currentAssignments: [DisplayAssignment] = []
    private var wallpapersByID: [UUID: VideoWallpaper] = [:]
    private var playbackPolicy: PlaybackPolicy?
    private var policyObservation: AnyCancellable?

    init() {
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.reconcileWindows() }
        }
    }

    deinit {
        if let screenChangeObserver { NotificationCenter.default.removeObserver(screenChangeObserver) }
    }

    /// Starts (or re-syncs) desktop playback for the given assignments. Call again whenever
    /// assignments, the wallpaper library, or playback settings change.
    func start(assignments: [DisplayAssignment], wallpapers: [VideoWallpaper], policy: PlaybackPolicy) {
        currentAssignments = assignments
        wallpapersByID = Dictionary(uniqueKeysWithValues: wallpapers.map { ($0.id, $0) })
        playbackPolicy = policy
        observePolicy(policy)
        isRunning = true
        reconcileWindows()
    }

    func stop() {
        isRunning = false
        for (displayID, window) in windows {
            setPosterIfAvailable(for: displayID)
            window.orderOut(nil)
        }
        windows.removeAll()
        renderers.removeAll()
        players.removeAll()
        activeDisplayCount = 0
    }

    func updateAssignments(_ assignments: [DisplayAssignment], wallpapers: [VideoWallpaper]) {
        currentAssignments = assignments
        wallpapersByID = Dictionary(uniqueKeysWithValues: wallpapers.map { ($0.id, $0) })
        guard isRunning else { return }
        reconcileWindows()
    }

    private func observePolicy(_ policy: PlaybackPolicy) {
        policyObservation = Publishers.CombineLatest(policy.$shouldPlay, policy.$settings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.applyPolicyToAllRenderers()
            }
    }

    private func applyPolicyToAllRenderers() {
        guard let policy = playbackPolicy else { return }
        let active = policy.shouldPlay
        for renderer in renderers.values {
            renderer.isPlaybackActive = active
            renderer.fitMode = policy.settings.fitMode
            renderer.frameRateCap = policy.settings.frameRateCap
        }
        for player in players.values {
            player.isMuted = policy.settings.isMuted
        }
    }

    private func reconcileWindows() {
        guard isRunning else { return }
        let screens = NSScreen.screens
        let currentScreenIDs = Set(screens.map(DisplayIdentity.stableID(for:)))

        for (displayID, window) in windows where !currentScreenIDs.contains(displayID) {
            window.orderOut(nil)
            windows.removeValue(forKey: displayID)
            renderers.removeValue(forKey: displayID)
            players.removeValue(forKey: displayID)
        }

        for screen in screens {
            let displayID = DisplayIdentity.stableID(for: screen)
            guard let assignment = currentAssignments.first(where: { $0.displayID == displayID }),
                  assignment.destinations.contains(.desktop),
                  let wallpaperID = assignment.wallpaperID,
                  let wallpaper = wallpapersByID[wallpaperID]
            else {
                removeWindow(for: displayID)
                continue
            }
            syncWindow(for: screen, displayID: displayID, wallpaper: wallpaper)
        }
        activeDisplayCount = windows.count
    }

    private func removeWindow(for displayID: String) {
        guard let window = windows[displayID] else { return }
        window.orderOut(nil)
        windows.removeValue(forKey: displayID)
        renderers.removeValue(forKey: displayID)
        players.removeValue(forKey: displayID)
    }

    private func syncWindow(for screen: NSScreen, displayID: String, wallpaper: VideoWallpaper) {
        let settings = playbackPolicy?.settings ?? PlaybackSettings()
        let shouldPlay = playbackPolicy?.shouldPlay ?? true

        if let existingPlayer = players[displayID],
           let currentAsset = (existingPlayer.currentItem?.asset as? AVURLAsset)?.url,
           currentAsset == wallpaper.fileURL {
            windows[displayID]?.setFrame(screen.frame, display: true)
            renderers[displayID]?.isPlaybackActive = shouldPlay
            return
        }

        removeWindow(for: displayID)

        let player = AVPlayer(url: wallpaper.fileURL)
        player.isMuted = settings.isMuted
        player.actionAtItemEnd = .none

        let renderer = DesktopVideoView(
            player: player,
            fitMode: settings.fitMode,
            frameRateCap: settings.frameRateCap,
            ciContext: ciContext
        )
        renderer.isPlaybackActive = shouldPlay

        let window = DesktopWindow(screen: screen)
        window.contentView = renderer
        window.setFrame(screen.frame, display: true)
        window.orderFront(nil)

        windows[displayID] = window
        renderers[displayID] = renderer
        players[displayID] = player

        if shouldPlay { player.play() }

        Task { await setPoster(for: displayID, wallpaper: wallpaper, screen: screen) }
    }

    private func setPosterIfAvailable(for displayID: String) {
        guard let screen = NSScreen.screens.first(where: { DisplayIdentity.stableID(for: $0) == displayID }),
              let assignment = currentAssignments.first(where: { $0.displayID == displayID }),
              let wallpaperID = assignment.wallpaperID,
              let wallpaper = wallpapersByID[wallpaperID]
        else { return }
        Task { await setPoster(for: displayID, wallpaper: wallpaper, screen: screen) }
    }

    private func setPoster(for displayID: String, wallpaper: VideoWallpaper, screen: NSScreen) async {
        guard let posterURL = await DesktopPosterGenerator.shared.posterURL(for: wallpaper) else { return }
        try? NSWorkspace.shared.setDesktopImageURL(posterURL, for: screen, options: [:])
    }
}

/// A borderless window that sits just behind the desktop-icon layer, ignores mouse input so
/// Finder icons and clicks pass through, and appears on every Space without joining the
/// window-cycling / Mission Control UI.
private final class DesktopWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        backgroundColor = .black
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) - 1)
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

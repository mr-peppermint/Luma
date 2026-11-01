import Combine
import Foundation

/// Decides whether Desktop playback should be running right now, purely from the settings
/// the product spec calls for (mute, fit/fill, pause on lock, pause on battery, FPS cap) and
/// the live signals from `PowerMonitor`. Applies no behavior on its own — callers observe
/// `shouldPlay` and act on it. `shouldPlay` is itself `@Published` (recomputed whenever
/// settings or power-monitor state change) so observers don't need to separately track
/// `PowerMonitor`.
@MainActor
final class PlaybackPolicy: ObservableObject {
    @Published var settings: PlaybackSettings {
        didSet { recompute() }
    }
    @Published private(set) var shouldPlay: Bool = true

    private let powerMonitor: PowerMonitor
    private var cancellable: AnyCancellable?

    init(settings: PlaybackSettings, powerMonitor: PowerMonitor) {
        self.settings = settings
        self.powerMonitor = powerMonitor
        cancellable = powerMonitor.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                // objectWillChange fires just before the new value lands; defer one runloop
                // turn so `recompute` reads the state that is about to be current.
                DispatchQueue.main.async { self?.recompute() }
            }
        recompute()
    }

    var isOnBatteryPower: Bool { powerMonitor.isOnBatteryPower }
    var isScreenLocked: Bool { powerMonitor.isScreenLocked }

    private func recompute() {
        if settings.pauseWhenLocked && powerMonitor.isScreenLocked {
            shouldPlay = false
        } else if settings.pauseOnBattery && powerMonitor.isOnBatteryPower {
            shouldPlay = false
        } else if powerMonitor.areDisplaysAsleep {
            shouldPlay = false
        } else {
            shouldPlay = true
        }
    }
}

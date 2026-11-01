import AppKit
import Combine
import IOKit.ps

/// Observes the signals `PlaybackPolicy` needs: whether the Mac is running on battery,
/// whether the screen is locked, and whether displays are asleep. Built entirely on public
/// `IOKit` power-source APIs and `NSWorkspace`/`DistributedNotificationCenter` notifications —
/// no private frameworks.
@MainActor
final class PowerMonitor: ObservableObject {
    @Published private(set) var isOnBatteryPower = false
    @Published private(set) var isScreenLocked = false
    @Published private(set) var areDisplaysAsleep = false

    private var runLoopSource: CFRunLoopSource?
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []

    init() {
        refreshPowerState()
        startBatteryObserving()
        startLockObserving()
        startSleepWakeObserving()
    }

    deinit {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        let distributed = DistributedNotificationCenter.default()
        for observer in distributedObservers { distributed.removeObserver(observer) }
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers { workspace.removeObserver(observer) }
    }

    private func startBatteryObserving() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in monitor.refreshPowerState() }
        }
        if let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
    }

    private func refreshPowerState() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, first)?.takeUnretainedValue() as? [String: Any]
        else {
            isOnBatteryPower = false
            return
        }
        let powerState = description[kIOPSPowerSourceStateKey] as? String
        isOnBatteryPower = powerState == kIOPSBatteryPowerValue
    }

    /// `com.apple.screenIsLocked`/`com.apple.screenIsUnlocked` are not formally documented
    /// in a public header, but they are ordinary `DistributedNotificationCenter` broadcasts
    /// (a fully public mechanism) that macOS has sent on every release for over a decade and
    /// that many shipping apps rely on. If a future macOS release stops sending them, this
    /// degrades silently to "never detects lock" rather than crashing or requiring a private
    /// framework.
    private func startLockObserving() {
        let center = DistributedNotificationCenter.default()
        let lockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.isScreenLocked = true } }
        let unlockObserver = center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.isScreenLocked = false } }
        distributedObservers = [lockObserver, unlockObserver]
    }

    private func startSleepWakeObserving() {
        let center = NSWorkspace.shared.notificationCenter
        let sleepObserver = center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.areDisplaysAsleep = true } }
        let wakeObserver = center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.areDisplaysAsleep = false } }
        workspaceObservers = [sleepObserver, wakeObserver]
    }
}

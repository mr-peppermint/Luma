import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var policy: PlaybackPolicy
    @EnvironmentObject private var rotation: RotationScheduler
    @EnvironmentObject private var powerMonitor: PowerMonitor
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    playbackSection
                    rotationSection
                    lockScreenSection
                    statusSection
                }
                .padding(28)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Settings")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Playback, battery, and rotation controls")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var playbackSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Theme.sectionHeader("PLAYBACK & BATTERY")

            Toggle("Mute audio", isOn: Binding(
                get: { policy.settings.isMuted },
                set: { policy.settings.isMuted = $0 }
            ))

            Picker("Video fit", selection: Binding(
                get: { policy.settings.fitMode },
                set: { policy.settings.fitMode = $0 }
            )) {
                ForEach(FitMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 220)

            Toggle("Pause when screen is locked", isOn: Binding(
                get: { policy.settings.pauseWhenLocked },
                set: { policy.settings.pauseWhenLocked = $0 }
            ))

            Toggle("Pause on battery power", isOn: Binding(
                get: { policy.settings.pauseOnBattery },
                set: { policy.settings.pauseOnBattery = $0 }
            ))

            Picker("Frame-rate cap", selection: Binding(
                get: { policy.settings.frameRateCap },
                set: { policy.settings.frameRateCap = $0 }
            )) {
                ForEach(FrameRateCap.allCases) { cap in
                    Text(cap.title).tag(cap)
                }
            }
            .frame(maxWidth: 220)
        }
    }

    private var rotationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Theme.sectionHeader("AUTOMATIC ROTATION")

            Picker("Rotate from", selection: Binding(
                get: { rotation.settings.scope },
                set: { rotation.settings.scope = $0 }
            )) {
                ForEach(RotationScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .frame(maxWidth: 260)

            if rotation.settings.scope == .collection {
                Picker("Collection", selection: Binding(
                    get: { rotation.settings.collectionID },
                    set: { rotation.settings.collectionID = $0 }
                )) {
                    Text("Choose a collection").tag(UUID?.none)
                    ForEach(appModel.collections) { collection in
                        Text(collection.name).tag(UUID?.some(collection.id))
                    }
                }
                .frame(maxWidth: 260)
            }

            if rotation.settings.scope != .off {
                Stepper(
                    "Every \(Int(rotation.settings.intervalMinutes)) minutes",
                    value: Binding(
                        get: { rotation.settings.intervalMinutes },
                        set: { rotation.settings.intervalMinutes = $0 }
                    ),
                    in: 1...360,
                    step: 1
                )
                .frame(maxWidth: 260)

                Toggle("Same video on every display", isOn: Binding(
                    get: { rotation.settings.syncAcrossDisplays },
                    set: { rotation.settings.syncAcrossDisplays = $0 }
                ))

                Button("Rotate Now") { rotation.rotateNow() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var lockScreenSection: some View {
        let status = LockScreenExperimentStatus.evaluate(isEnabled: policy.settings.lockScreenExperimentEnabled)
        return VStack(alignment: .leading, spacing: 10) {
            Theme.sectionHeader("LOCK SCREEN (EXPERIMENTAL)")
            Toggle("Enable experimental Lock Screen playback", isOn: Binding(
                get: { policy.settings.lockScreenExperimentEnabled },
                set: { policy.settings.lockScreenExperimentEnabled = $0 }
            ))
            Text(status.message)
                .font(.caption)
                .foregroundStyle(.orange)
            Text("macOS has no public API for animated Lock Screen wallpaper. This switch only turns on a diagnostic check — it never claims animated Lock Screen support is working.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Theme.sectionHeader("LIVE STATUS")
            HStack(spacing: 8) {
                Circle().fill(powerMonitor.isOnBatteryPower ? Color.orange : Color.green).frame(width: 7, height: 7)
                Text(powerMonitor.isOnBatteryPower ? "Running on battery" : "Running on AC power")
            }
            HStack(spacing: 8) {
                Circle().fill(powerMonitor.isScreenLocked ? Color.orange : Color.green).frame(width: 7, height: 7)
                Text(powerMonitor.isScreenLocked ? "Screen is locked" : "Screen is unlocked")
            }
            HStack(spacing: 8) {
                Circle().fill(policy.shouldPlay ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(policy.shouldPlay ? "Playback policy: active" : "Playback policy: paused")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

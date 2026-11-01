import SwiftUI

struct DisplaysView: View {
    @EnvironmentObject private var appModel: AppModel
    @EnvironmentObject private var coordinator: DesktopWallpaperCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sameVideoAction
                    ForEach(appModel.availableDisplays) { display in
                        DisplayRow(display: display)
                    }
                    if appModel.availableDisplays.isEmpty {
                        Text("No displays detected.")
                            .foregroundStyle(.secondary)
                    }
                    limitationsNote
                }
                .padding(28)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Displays")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Assign wallpapers per display and control Desktop playback")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if coordinator.isRunning {
                    appModel.stopDesktopPlayback()
                } else {
                    appModel.startDesktopPlayback()
                }
            } label: {
                Label(coordinator.isRunning ? "Stop Desktop Playback" : "Start Desktop Playback",
                      systemImage: coordinator.isRunning ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(coordinator.isRunning ? .red : Theme.accent)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var mainDisplayWallpaper: VideoWallpaper? {
        guard let first = appModel.availableDisplays.first else { return nil }
        guard let wallpaperID = appModel.assignment(for: first).wallpaperID else { return nil }
        return appModel.wallpapers.first { $0.id == wallpaperID }
    }

    private var sameVideoAction: some View {
        Button {
            guard let wallpaper = mainDisplayWallpaper else { return }
            appModel.assignWallpaperToAllDisplays(wallpaper)
        } label: {
            Label("Use main display's video on every display", systemImage: "square.on.square")
        }
        .buttonStyle(.bordered)
        .disabled(mainDisplayWallpaper == nil)
    }

    private var limitationsNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Theme.sectionHeader("ABOUT DESKTOP PLAYBACK")
            Text("Luma plays video through an app-owned window placed just behind your desktop icons — macOS has no public API to set a video as the actual desktop picture. This can behave differently across Spaces, Mission Control, fullscreen apps, and sleep/wake, and if Luma quits the animation stops (a still frame remains as the system wallpaper).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }
}

private struct DisplayRow: View {
    @EnvironmentObject private var appModel: AppModel
    let display: DisplayInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: display.isMain ? "display" : "display.2")
                Text(display.name).font(.headline)
                if display.isMain { PillBadge(text: "MAIN") }
                Spacer()
            }

            let assignment = appModel.assignment(for: display)
            let assignedWallpaper = assignment.wallpaperID.flatMap { id in appModel.wallpapers.first { $0.id == id } }

            Picker("Wallpaper", selection: Binding<UUID?>(
                get: { assignment.wallpaperID },
                set: { newID in
                    guard let newID else { return }
                    let destinations = assignment.destinations.isEmpty ? [WallpaperDestination.desktop] : assignment.destinations
                    appModel.updateAssignment(for: display, wallpaperID: newID, destinations: destinations)
                }
            )) {
                Text("None").tag(UUID?.none)
                ForEach(appModel.wallpapers) { wallpaper in
                    Text(wallpaper.title).tag(UUID?.some(wallpaper.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)

            if assignedWallpaper != nil {
                HStack(spacing: 16) {
                    ForEach(WallpaperDestination.allCases) { destination in
                        Toggle(destination.title, isOn: Binding(
                            get: { assignment.destinations.contains(destination) },
                            set: { newValue in
                                var destinations = assignment.destinations
                                if newValue { destinations.insert(destination) } else { destinations.remove(destination) }
                                appModel.updateAssignment(for: display, wallpaperID: assignment.wallpaperID, destinations: destinations)
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }
}

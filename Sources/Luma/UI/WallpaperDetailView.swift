import SwiftUI

struct WallpaperDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let wallpaper: VideoWallpaper

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            PreviewPlayerView(url: wallpaper.fileURL)
                .frame(height: 280)
                .background(Color.black)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    metadataRow
                    collectionsSection
                    destinationsSection
                    if let provenance = wallpaper.workshopInfo {
                        provenanceSection(provenance)
                    }
                }
                .padding(24)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack {
            Text(wallpaper.title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Spacer()
            Button {
                appModel.toggleFavorite(wallpaper)
            } label: {
                Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(wallpaper.isFavorite ? .pink : .secondary)
            }
            .buttonStyle(.plain)
            Button("Close") { dismiss() }
        }
        .padding(16)
    }

    private var metadataRow: some View {
        HStack(spacing: 14) {
            PillBadge(text: wallpaper.origin == .local ? "LOCAL" : "WORKSHOP")
            if let width = wallpaper.pixelWidth, let height = wallpaper.pixelHeight {
                Text("\(width) × \(height)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let duration = wallpaper.durationSeconds {
                Text(formattedDuration(duration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                appModel.removeWallpaper(wallpaper)
                dismiss()
            } label: {
                Label("Remove", systemImage: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.sectionHeader("COLLECTIONS")
            if appModel.collections.isEmpty {
                Text("No collections yet. Create one from the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(appModel.collections) { collection in
                        let isMember = wallpaper.collectionIDs.contains(collection.id)
                        Button {
                            appModel.toggleMembership(of: wallpaper, in: collection)
                        } label: {
                            Label(collection.name, systemImage: isMember ? "checkmark" : "plus")
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(isMember ? Theme.accent.opacity(0.25) : .white.opacity(0.07), in: Capsule())
                    }
                }
            }
        }
    }

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Theme.sectionHeader("DISPLAYS & DESTINATIONS")
            Button {
                appModel.assignWallpaperToAllDisplays(wallpaper)
            } label: {
                Label("Use on every display (Desktop)", systemImage: "square.on.square")
            }
            .buttonStyle(.bordered)

            ForEach(appModel.availableDisplays) { display in
                let assignment = appModel.assignment(for: display)
                let isAssignedHere = assignment.wallpaperID == wallpaper.id
                HStack {
                    Image(systemName: display.isMain ? "display" : "display.2")
                    Text(display.name)
                    Spacer()
                    ForEach(WallpaperDestination.allCases) { destination in
                        Toggle(destination.title, isOn: Binding(
                            get: { isAssignedHere && assignment.destinations.contains(destination) },
                            set: { newValue in
                                var destinations = isAssignedHere ? assignment.destinations : []
                                if newValue { destinations.insert(destination) } else { destinations.remove(destination) }
                                appModel.updateAssignment(for: display, wallpaperID: wallpaper.id, destinations: destinations)
                            }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func provenanceSection(_ provenance: WorkshopProvenance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Theme.sectionHeader("STEAM WORKSHOP")
            Text("Workshop ID: \(provenance.workshopID)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Imported from: \(provenance.sourceFolderPath)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func formattedDuration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: seconds) ?? ""
    }
}

/// Minimal wrapping flow layout for collection chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > maxWidth, origin.x > 0 {
                origin.x = 0
                origin.y += rowHeight + spacing
                totalHeight += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: maxWidth.isFinite ? maxWidth : origin.x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.origin.x {
                origin.x = bounds.origin.x
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

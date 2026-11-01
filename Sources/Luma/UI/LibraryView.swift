import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    let section: LibrarySection
    let collectionID: UUID?

    private let columns = [GridItem(.adaptive(minimum: 210), spacing: 18)]

    private var items: [VideoWallpaper] {
        let base: [VideoWallpaper]
        switch section {
        case .all: base = appModel.wallpapers
        case .favorites: base = appModel.wallpapers.filter(\.isFavorite)
        case .recent: base = appModel.wallpapers.sorted { $0.dateAdded > $1.dateAdded }
        case .local: base = appModel.wallpapers.filter { $0.origin == .local }
        case .workshop: base = appModel.wallpapers.filter { $0.origin == .steamWorkshop }
        }
        let collectionFiltered = collectionID.map { id in base.filter { $0.collectionIDs.contains(id) } } ?? base
        guard !appModel.searchText.isEmpty else { return collectionFiltered }
        return collectionFiltered.filter { $0.title.localizedCaseInsensitiveContains(appModel.searchText) }
    }

    private var title: String {
        if let collectionID, let collection = appModel.collections.first(where: { $0.id == collectionID }) {
            return collection.name
        }
        return section.title
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if items.isEmpty {
                emptyState
            } else {
                grid
            }
        }
        .sheet(item: Binding(
            get: { appModel.selectedWallpaperID.flatMap { id in appModel.wallpapers.first { $0.id == id } } },
            set: { newValue in appModel.selectedWallpaperID = newValue?.id }
        )) { wallpaper in
            WallpaperDetailView(wallpaper: wallpaper)
                .frame(minWidth: 560, minHeight: 520)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("Your personal motion library")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search wallpapers", text: $appModel.searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 170)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            Button {
                appModel.isShowingImporter = true
            } label: {
                Label("Import Video", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(items) { wallpaper in
                    WallpaperCard(
                        wallpaper: wallpaper,
                        isSelected: appModel.selectedWallpaperID == wallpaper.id,
                        favoriteAction: { appModel.toggleFavorite(wallpaper) }
                    ) {
                        appModel.selectedWallpaperID = wallpaper.id
                    }
                }
            }
            .padding(28)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(.white.opacity(0.045)).frame(width: 94, height: 94)
                Image(systemName: "play.rectangle.on.rectangle")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(Theme.accentLight)
            }
            Text(appModel.wallpapers.isEmpty ? "Your library starts here" : "No matches")
                .font(.system(size: 23, weight: .semibold, design: .rounded))
            Text(appModel.wallpapers.isEmpty ? "Add an MP4 or MOV and turn it into a living desktop." : "Try a different search or section.")
                .foregroundStyle(.secondary)
            if appModel.wallpapers.isEmpty {
                Button("Import your first video") { appModel.isShowingImporter = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct WallpaperCard: View {
    let wallpaper: VideoWallpaper
    let isSelected: Bool
    let favoriteAction: () -> Void
    let selectAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .frame(height: 145)
                    .clipped()
                Button(action: favoriteAction) {
                    Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(wallpaper.isFavorite ? .pink : .white)
                        .padding(9)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(.plain)
                .padding(10)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(wallpaper.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                HStack {
                    Text(wallpaper.dimensionsLabel).foregroundStyle(.secondary)
                    Spacer()
                    PillBadge(text: wallpaper.origin == .local ? "LOCAL" : "WORKSHOP")
                }
                .font(.caption2)
            }
            .padding(12)
        }
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? Theme.accent : .white.opacity(0.07), lineWidth: isSelected ? 1.5 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: selectAction)
    }

    @ViewBuilder private var thumbnail: some View {
        ZStack {
            if let thumbnailURL = wallpaper.thumbnailURL, let image = NSImage(contentsOf: thumbnailURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(LinearGradient(colors: [Color.indigo.opacity(0.28), Color.cyan.opacity(0.12), .black.opacity(0.45)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            Image(systemName: "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.85))
                .padding(18)
                .background(.black.opacity(0.35), in: Circle())
        }
    }
}

private extension VideoWallpaper {
    var dimensionsLabel: String {
        guard let pixelWidth, let pixelHeight else { return fileURL.pathExtension.uppercased() }
        return "\(pixelWidth) × \(pixelHeight)"
    }
}

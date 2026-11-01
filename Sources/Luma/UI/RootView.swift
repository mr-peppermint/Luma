import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: Hashable {
    case library(LibrarySection)
    case collection(UUID)
    case displays
    case workshop
    case settings
}

struct RootView: View {
    @EnvironmentObject private var appModel: AppModel
    @StateObject private var selectionBox = StateBox<SidebarItem?>(.library(.all))
    @StateObject private var newCollectionPrompt = StateBox(false)
    @StateObject private var newCollectionName = StateBox("")

    private var selection: Binding<SidebarItem?> {
        Binding(get: { selectionBox.value }, set: { selectionBox.value = $0 })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            detail
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color.black.opacity(0.12))
        .fileImporter(
            isPresented: $appModel.isShowingImporter,
            allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            if case let .success(urls) = result {
                Task { await appModel.importVideos(urls) }
            }
        }
        .alert("Couldn't import video", isPresented: Binding(
            get: { appModel.importError != nil },
            set: { if !$0 { appModel.importError = nil } }
        )) {
            Button("OK", role: .cancel) { appModel.importError = nil }
        } message: {
            Text(appModel.importError ?? "")
        }
        .alert("New Collection", isPresented: Binding(
            get: { newCollectionPrompt.value },
            set: { newCollectionPrompt.value = $0 }
        )) {
            TextField("Collection name", text: Binding(
                get: { newCollectionName.value },
                set: { newCollectionName.value = $0 }
            ))
            Button("Create") {
                appModel.createCollection(named: newCollectionName.value)
                newCollectionName.value = ""
            }
            Button("Cancel", role: .cancel) { newCollectionName.value = "" }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            Section("LIBRARY") {
                Label("All Wallpapers", systemImage: "square.grid.2x2.fill")
                    .tag(SidebarItem.library(.all))
                Label("Favorites", systemImage: "heart.fill")
                    .tag(SidebarItem.library(.favorites))
                Label("Recently Added", systemImage: "clock")
                    .tag(SidebarItem.library(.recent))
            }
            Section("SOURCES") {
                Label("My Videos", systemImage: "film")
                    .tag(SidebarItem.library(.local))
                Label("Workshop Videos", systemImage: "shippingbox")
                    .tag(SidebarItem.library(.workshop))
            }
            Section("COLLECTIONS") {
                ForEach(appModel.collections) { collection in
                    Label(collection.name, systemImage: "folder.fill")
                        .tag(SidebarItem.collection(collection.id))
                        .contextMenu {
                            Button("Delete Collection", role: .destructive) {
                                appModel.deleteCollection(collection)
                            }
                        }
                }
                Button {
                    newCollectionPrompt.value = true
                } label: {
                    Label("New Collection", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            Section("MANAGE") {
                Label("Displays", systemImage: "display.2")
                    .tag(SidebarItem.displays)
                Label("Steam Workshop", systemImage: "arrow.down.circle")
                    .tag(SidebarItem.workshop)
                Label("Settings", systemImage: "gearshape.fill")
                    .tag(SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            StatusFooter()
        }
    }

    @ViewBuilder private var detail: some View {
        switch selectionBox.value {
        case .library(let section):
            LibraryView(section: section, collectionID: nil)
        case .collection(let id):
            LibraryView(section: .all, collectionID: id)
        case .displays:
            DisplaysView()
        case .workshop:
            WorkshopView()
        case .settings:
            SettingsView()
        case nil:
            LibraryView(section: .all, collectionID: nil)
        }
    }
}

private struct StatusFooter: View {
    @EnvironmentObject private var coordinator: DesktopWallpaperCoordinator

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(coordinator.isRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(coordinator.isRunning ? "Desktop playback running · \(coordinator.activeDisplayCount) display(s)" : "Desktop playback stopped")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }
}

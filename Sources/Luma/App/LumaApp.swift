import SwiftUI

@main
struct LumaApp: App {
    @StateObject private var env = AppEnvironment()
    @StateObject private var appModel: AppModel
    @StateObject private var workshopModel: WorkshopViewModel

    init() {
        let env = AppEnvironment()
        _env = StateObject(wrappedValue: env)
        let appModel = AppModel(env: env)
        _appModel = StateObject(wrappedValue: appModel)
        let workshopModel = WorkshopViewModel(env: env)
        workshopModel.onLibraryChanged = { [weak appModel] in
            await appModel?.reloadWallpapers()
        }
        _workshopModel = StateObject(wrappedValue: workshopModel)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .environmentObject(env)
                .environmentObject(workshopModel)
                .environmentObject(env.playbackPolicy)
                .environmentObject(env.rotationScheduler)
                .environmentObject(env.desktopCoordinator)
                .environmentObject(env.powerMonitor)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1040, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

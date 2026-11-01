import Foundation

/// Finds plausible Steam library folders on disk so the user doesn't always have to browse
/// manually. Never assumes Steam is installed; every result is verified to exist before
/// being offered, and manual folder selection is always available regardless of what this
/// finds.
struct SteamLibraryLocator {
    private let fileManager = FileManager.default

    /// Common locations for the macOS Steam client's default library and the Wallpaper
    /// Engine Workshop content folder within it. Steam supports additional user-configured
    /// libraries (via `libraryfolders.vdf`) that this does not parse; manual selection
    /// covers those.
    func likelyWorkshopContentFolders() -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/Steam/steamapps/workshop/content/\(wallpaperEngineWorkshopAppID)"),
            home.appendingPathComponent("Steam/steamapps/workshop/content/\(wallpaperEngineWorkshopAppID)"),
        ]
        return candidates.filter { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    func likelySteamLibraryRoots() -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/Steam"),
            home.appendingPathComponent("Steam"),
        ]
        return candidates.filter { url in
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }
}

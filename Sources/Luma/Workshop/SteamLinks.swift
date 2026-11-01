import Foundation

/// Links to Steam's own Workshop pages. Luma never talks to Steam programmatically for
/// discovery, subscription, or download — it only opens these URLs in the user's browser
/// or Steam client and lets Steam handle sign-in and downloads.
enum SteamLinks {
    static var wallpaperEngineWorkshopURL: URL {
        URL(string: "https://steamcommunity.com/app/\(wallpaperEngineWorkshopAppID)/workshop/")!
    }

    static func workshopItemURL(id: String) -> URL? {
        guard let numeric = UInt64(id) else { return nil }
        return URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(numeric)")
    }

    /// Steam's own `steam://` URL scheme, handled by the Steam client when installed.
    static func steamClientWorkshopItemURL(id: String) -> URL? {
        guard let numeric = UInt64(id) else { return nil }
        return URL(string: "steam://url/CommunityFilePage/\(numeric)")
    }
}

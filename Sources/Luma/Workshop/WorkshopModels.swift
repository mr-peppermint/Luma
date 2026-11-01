import Foundation

/// Wallpaper Engine's Workshop App ID on Steam. Used only to recognize the on-disk content
/// folder layout (`steamapps/workshop/content/431960/<itemID>`). Luma has no Steamworks
/// authorization for this App ID and never calls any Steam Web/UGC API with it — it only
/// reads files the user already has on disk after Steam downloaded them.
let wallpaperEngineWorkshopAppID = "431960"

/// The declared type of a Wallpaper Engine Workshop item, read from its `project.json`
/// when present. Only `.video` is importable by this app.
enum WorkshopItemKind: String {
    case video
    case scene
    case web
    case application
    case unknown

    init(projectType: String?) {
        switch projectType?.lowercased() {
        case "video": self = .video
        case "scene": self = .scene
        case "web", "webgl": self = .web
        case "application", "app": self = .application
        default: self = .unknown
        }
    }
}

/// Minimal subset of Wallpaper Engine's `project.json` schema that Luma reads. Any other
/// fields present in the file are ignored. Parsing failures are treated as "no metadata,"
/// never as a reason to reject the item outright.
struct WorkshopProjectMetadata: Decodable {
    var title: String?
    var type: String?
    var file: String?
    var preview: String?
}

enum WorkshopItemStatus: Equatable {
    case readyToImport
    case alreadyInLibrary
    case unsupported(reason: String)
}

/// One discovered Workshop item folder, with every video file candidate found inside it.
/// `selectedCandidateIndex` lets the UI ask the user to disambiguate when there's more
/// than one plausible video.
struct WorkshopScanResult: Identifiable {
    var id: String { workshopID }
    var workshopID: String
    var folderURL: URL
    var title: String
    var declaredKind: WorkshopItemKind
    var candidateVideoFiles: [URL]
    var previewImageURL: URL?
    var totalSizeBytes: Int64
    var status: WorkshopItemStatus
}

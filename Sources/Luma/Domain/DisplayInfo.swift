import AppKit

/// A currently-connected display, identified by its stable hardware UUID rather than its
/// position in `NSScreen.screens`.
struct DisplayInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var isMain: Bool

    static func current() -> [DisplayInfo] {
        NSScreen.screens.map { screen in
            DisplayInfo(
                id: DisplayIdentity.stableID(for: screen),
                name: DisplayIdentity.displayName(for: screen),
                isMain: screen == NSScreen.main
            )
        }
    }
}

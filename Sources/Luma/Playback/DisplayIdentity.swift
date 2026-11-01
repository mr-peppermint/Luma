import AppKit

/// Stable, persistent display identifiers. `NSScreen.screens` order changes whenever a
/// display is connected, disconnected, or put to sleep, so assignments are keyed on the
/// display's hardware UUID instead of array position.
enum DisplayIdentity {
    static func stableID(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        let directID = CGDirectDisplayID(number.uint32Value)
        if let uuid = CGDisplayCreateUUIDFromDisplayID(directID)?.takeRetainedValue() {
            return CFUUIDCreateString(nil, uuid) as String
        }
        return "display-\(directID)"
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }

    static func displayName(for screen: NSScreen) -> String {
        screen.localizedName
    }
}

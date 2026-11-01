import Foundation

/// Isolated, opt-in investigation of animated Lock Screen playback. There is no public
/// macOS API for this. This adapter never links against any private framework at compile
/// time — the main app target has zero build-time dependency on it — and it never calls
/// undocumented symbols by guessed name, which would be unstable across macOS releases and
/// is not something this project will reverse-engineer blindly.
///
/// What it actually does, only when the user turns on the experimental setting: check,
/// using ordinary file-system access (never loading or linking it), whether
/// `WallpaperExtensionKit` — the private framework macOS's own System Settings uses for
/// Sonoma-and-later wallpaper rendering — is present on this machine, purely as a
/// diagnostic. It never loads, links, or calls into it, because there is no public, stable,
/// documented entry point to call safely. The result is always that animated Lock Screen
/// playback is unavailable; this adapter exists so that boundary is explicit and isolated
/// rather than silently absent.
enum LockScreenAvailability {
    case unavailable(reason: String)

    static func current() -> LockScreenAvailability {
        .unavailable(reason: describeAvailability())
    }

    private static func describeAvailability() -> String {
        let path = "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"
        guard FileManager.default.fileExists(atPath: path) else {
            return "Experimental Lock Screen playback unavailable — no supported integration exists on this macOS version."
        }
        return "Experimental Lock Screen playback unavailable — the system framework that backs Lock Screen wallpaper rendering was found, but it is private and has no documented, stable public interface Luma can call safely. Luma will not guess at undocumented symbols."
    }
}

/// UI-facing status for the Lock Screen destination. Desktop playback never depends on
/// this type or on anything in the `LockScreen` module.
struct LockScreenExperimentStatus {
    var isEnabled: Bool
    var message: String

    static func evaluate(isEnabled: Bool) -> LockScreenExperimentStatus {
        guard isEnabled else {
            return LockScreenExperimentStatus(isEnabled: false, message: "Experimental Lock Screen playback is turned off.")
        }
        switch LockScreenAvailability.current() {
        case .unavailable(let reason):
            return LockScreenExperimentStatus(isEnabled: true, message: reason)
        }
    }
}

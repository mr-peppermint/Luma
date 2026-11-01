# Luma — architecture and API boundaries

This describes the implementation as built, not a plan. It's organized around the one
question that matters most for a wallpaper app: for each capability, what is actually
public/supported, and what is an app-level technique with real limits.

## Platform capability matrix

| Capability | Status | How Luma implements it |
| --- | --- | --- |
| Read/validate MP4/MOV, extract metadata | Public API | `AVURLAsset` + `AVAssetImageGenerator` (`Sources/Luma/Import/VideoImportService.swift`). A file is only accepted once AVFoundation reports it `isPlayable` and exposes a video track — extension matching alone is never trusted. |
| Still Desktop picture | Public API | `NSWorkspace.setDesktopImageURL(_:for:options:)`. Luma uses this for a poster frame (`Sources/Luma/Playback/DesktopPosterGenerator.swift`) set before/after animated playback — it is a real image, not a stand-in for video. |
| Animated Desktop wallpaper | **App-managed technique, not a system API** | One borderless, click-through `NSWindow` per `NSScreen`, placed at `CGWindowLevelForKey(.desktopIconWindow) - 1` (behind Finder icons, above the desktop picture). Frames are pulled from `AVPlayerItemVideoOutput` and drawn via `NSView.displayLink(target:selector:)` (macOS 14+), so the frame-rate cap setting is a real throttle, not a label. See `Sources/Luma/Playback/DesktopWallpaperCoordinator.swift` and `DesktopVideoView.swift`. **Limits that are real, not hypothetical:** if Luma quits or crashes, the animated window disappears immediately (the poster frame remains as the system wallpaper); behavior around Mission Control, full-space switches, fullscreen apps, and multi-GPU/external-display reconfiguration has not been exercised on more than one physical display in this environment and can vary by macOS release. |
| Animated Lock Screen wallpaper | **Not implemented. No public API exists.** | `Sources/Luma/LockScreen/LockScreenAdapter.swift` is the entire Lock Screen module. It never links against any private framework — it only checks, via ordinary file-existence checks (never `dlopen`/`dlsym`/linking), whether `WallpaperExtensionKit` (the private framework behind System Settings' own Sonoma+ wallpaper rendering) is present, purely to report that status. It always concludes "Experimental Lock Screen playback unavailable." The main app target has zero compile-time or runtime dependency on this module's internals, and the Settings UI never claims this works. |
| Multiple displays | Public API + app bookkeeping | `CGDisplayCreateUUIDFromDisplayID` gives a stable per-display identifier (`Sources/Luma/Playback/DisplayIdentity.swift`), so assignments survive `NSScreen.screens` reordering when displays connect/disconnect. `DesktopWallpaperCoordinator` reconciles windows against `NSApplication.didChangeScreenParametersNotification`. |
| Battery/lock-aware playback | Public API | `IOKit`'s `IOPSCopyPowerSourcesInfo`/`IOPSNotificationCreateRunLoopSource` for battery state; `NSWorkspace.screensDidSleepNotification`/`screensDidWakeNotification` for display sleep. Screen-lock detection uses `DistributedNotificationCenter` with the `com.apple.screenIsLocked`/`com.apple.screenIsUnlocked` notification names — these aren't in a public header, but they are ordinary `DistributedNotificationCenter` broadcasts (a fully public API) that macOS has sent for many releases; if a future release stops sending them, lock-detection silently stops working rather than breaking anything. See `Sources/Luma/Power/PowerMonitor.swift`. |
| Steam Workshop discovery/download | **Not an app-owned integration — delegated to Steam** | Luma has no Steamworks App ID and does not call `ISteamUGC` or any Workshop web API. It opens `steamcommunity.com/app/431960/workshop` and individual item pages in the browser/Steam client (`Sources/Luma/Workshop/SteamLinks.swift`), and separately offers a read-only local folder scan + import once Steam has already downloaded content to disk. |

## Module map (as built)

```text
Sources/Luma/
  App/          AppEnvironment (DI container), AppModel (library/collections/assignments
                state + persistence), WorkshopViewModel, LumaApp entry point.
  Domain/       VideoWallpaper, WallpaperCollection, DisplayAssignment, PlaybackSettings,
                RotationSettings, DisplayInfo — no AppKit/SwiftUI/AVFoundation dependencies
                except DisplayInfo's use of NSScreen for enumeration.
  Library/      WallpaperRepository protocol + JSONWallpaperRepository, the single
                persisted document for wallpapers, collections, display assignments, and
                settings.
  Import/       VideoImportService: MP4/MOV validation, AVFoundation readability probe,
                thumbnail generation, managed-storage copy. Shared by both the manual
                importer and the Workshop importer.
  Workshop/     SteamLibraryLocator (best-effort folder detection), WorkshopScanner
                (bounded, symlink-safe, read-only directory walk + project.json parsing),
                WorkshopImporter (copy + provenance/fingerprint), SteamLinks.
  Playback/     DesktopWallpaperCoordinator, DesktopVideoView (the FPS-capped renderer),
                DesktopPosterGenerator, PlaybackPolicy, PreviewPlayerView (in-app preview),
                DisplayIdentity.
  Rotation/     RotationScheduler — timer-driven, scope/interval/sync-across-displays.
  Power/        PowerMonitor — battery, lock, and display-sleep signals.
  LockScreen/   LockScreenAdapter — isolated, always reports unavailable; see above.
  UI/           RootView (sidebar/navigation), LibraryView, WallpaperDetailView,
                DisplaysView, WorkshopView, SettingsView, shared Theme/StateBox helpers.
```

### Why a JSON document instead of SwiftData

`WallpaperRepository` persists one versioned JSON document (`library.json`, with a
`schemaVersion` field) covering wallpapers, collections, display assignments, and settings.
This app's data model is small, has no relational queries, and is never searched outside
of simple in-memory array filtering — SwiftData's query/relationship machinery would add
complexity without a matching benefit here. Large binary assets (videos, thumbnails,
posters) are never stored in this document; only their file URLs are, with the files
themselves under `~/Library/Application Support/Luma/`.

### Why `@StateObject` instead of `@State` in places that look unusual

The toolchain available while building this project is Xcode's Command Line Tools without
the Xcode.app bundle. That toolchain has no `SwiftUIMacros` plugin binary, which modern
SwiftUI needs to expand the `@State` property wrapper macro — so `@State` fails to compile
in this environment specifically (confirmed by direct testing; `@Binding`, `@Environment`,
and `@StateObject` are unaffected). A small `StateBox<Value>: ObservableObject` helper
(`Sources/Luma/UI/StateBox.swift`) stands in for `@State` wherever view-local state is
needed. On a machine with full Xcode installed, `@State` would work fine; this substitution
exists only because of the environment this was built in, not a design preference, and is
documented here so it isn't mistaken for one.

## Steam Workshop import, precisely

1. **Discovery/subscription/download is 100% Steam's.** Luma opens official Steam URLs and
   never touches Steam credentials, session cookies, or any private/unofficial endpoint.
2. **Detection** (`SteamLibraryLocator`) checks a couple of common macOS Steam library paths
   and always allows manual folder selection via the system file picker — it never assumes
   Steam is installed.
3. **Scanning** (`WorkshopScanner`) resolves the chosen folder to a Workshop content
   directory (recognizing `steamapps/workshop/content/431960` or a folder of item-ID
   subfolders), then walks each item folder up to 3 levels deep. It never follows a symlink
   that resolves outside the item folder, never extracts archives, and never executes
   anything — it only reads file metadata and, when present, parses `project.json` as JSON
   (never as code). A candidate file is only called "ready to import" once
   `VideoImportService.probe` confirms AVFoundation can actually decode it. Scene, web, and
   application-type Workshop items (per `project.json`'s `type` field) are always reported
   unsupported, never guessed at or partially rendered.
4. **Importing** (`WorkshopImporter`) copies the chosen video into managed storage and
   records its Workshop ID, source folder path, and a fingerprint (size + mtime + path
   hash) — never modifying or deleting anything under the Steam folder. Re-scanning checks
   that fingerprint against the library so the same item isn't copied twice.
5. If an item has more than one plausible video file, the UI asks the user which one to
   import (`WorkshopViewModel.pendingDisambiguation`) rather than guessing.

## Known limitations (stated plainly)

- **No public API sets a video as the Desktop picture or the Lock Screen.** Both
  limitations above are real, not an implementation gap Luma is hiding.
- **Only verified on a single physical display.** The multi-display code path (stable
  per-display IDs, independent/synced assignment, window reconciliation on screen changes)
  was exercised through the persistence layer directly — same video assigned to two
  synthetic display IDs round-trips correctly through `WallpaperRepository` — and the
  Desktop window was confirmed to appear at the correct window level and full-screen bounds
  on the one real display available. It has not been exercised on real multiple monitors.
- **`xcodebuild` was not available in the environment this was built in** (Command Line
  Tools only, no Xcode.app). The `.xcodeproj` was generated with XcodeGen from
  `project.yml` and its `project.pbxproj` was validated structurally, but an actual Xcode
  build of the `.xcodeproj` target has not been run end-to-end on this machine. `swift
  build` against the identical source tree has been run and passes repeatedly with no
  warnings beyond two pre-existing linker search-path warnings caused by the missing
  Xcode.app Developer directory.
- **No GUI screenshot verification.** This environment has no Screen Recording/Accessibility
  permission available to capture pixels, so visual confirmation of rendered video frames
  was not possible. Functional verification used the real production types directly (a
  small harness compiled against the actual `VideoImportService`, `WallpaperRepository`,
  `WorkshopScanner`, and `WorkshopImporter` source files — not a reimplementation) plus
  window-list inspection (`CGWindowListCopyWindowInfo`) confirming the Desktop playback
  window is created at the exact intended `CGWindowLevel` and full-screen bounds.

## References

- [Apple: `NSWorkspace.setDesktopImageURL`](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:))
- [Apple: `AVPlayerItemVideoOutput`](https://developer.apple.com/documentation/avfoundation/avplayeritemvideooutput)
- [Apple: `NSView.displayLink(target:selector:)`](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:))
- [Steamworks: `ISteamUGC`](https://partner.steamgames.com/doc/api/ISteamUGC)
- [Steamworks: Workshop implementation guide](https://partner.steamgames.com/doc/features/workshop/implementation)
- [Wallpaper Engine Workshop (Steam)](https://steamcommunity.com/app/431960/workshop/)
- [Wallpaper Engine documentation](https://docs.wallpaperengine.io/)

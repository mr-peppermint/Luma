# Project context — Luma

## Purpose

Native, video-only macOS wallpaper app: premium dark SwiftUI library with search,
favorites, collections, and previews; animated Desktop playback via an app-managed window;
per-display assignment (including "same video on every display"); Desktop/Lock Screen
destination choices (Lock Screen explicitly experimental and non-functional, by design —
see below); mute/fit/pause-on-lock/pause-on-battery/frame-rate-cap controls; automatic
rotation; and Steam Workshop discovery + local-folder import for Wallpaper Engine video
items.

## Status: implemented, not a scaffold

Every feature in the original product brief has a real implementation under
`Sources/Luma/` — there are no placeholder buttons, no fake services, and no feature
described as working that isn't. The two capabilities macOS doesn't expose publicly
(animated Desktop-as-wallpaper, animated Lock Screen) are implemented as the closest real
alternative (Desktop) or explicitly marked unavailable (Lock Screen) rather than faked. See
`docs/ARCHITECTURE.md` for the full capability-by-capability breakdown.

## Build status

- `swift build` (Swift Package target, `Package.swift`) **succeeds with zero errors and
  zero warnings from this project's code.** The only warnings are two pre-existing linker
  search-path warnings (`ld: warning: search path '.../Developer/usr/lib' not found`, etc.)
  caused by this machine having Xcode's Command Line Tools without the full Xcode.app —
  they existed before this work started and are unrelated to any code here.
- The Xcode project (`Luma.xcodeproj`) was generated with
  [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml` against the same
  `Sources/Luma` tree. `plutil -lint` confirms `project.pbxproj` is structurally valid.
  **`xcodebuild` is not installed on this machine** (no Xcode.app, only Command Line
  Tools), so the `.xcodeproj` build itself could not be run end-to-end here. On a machine
  with Xcode installed, open `Luma.xcodeproj` and build the `Luma` scheme (or run
  `xcodebuild -scheme Luma -project Luma.xcodeproj build`) to confirm it independently.
- A note on `@State`: this toolchain has no `SwiftUIMacros` plugin binary, so `@State`
  (which modern SwiftUI expands via a macro) fails to compile here specifically — confirmed
  by isolated testing. `Sources/Luma/UI/StateBox.swift` is a small `ObservableObject`
  substitute used in its place. This is an environment workaround, not a design choice;
  it's safe to replace with `@State` on a machine with full Xcode if preferred.

## Manual verification performed

Flows verified against the real production code (not a reimplementation):

- **Import MP4 / import MOV**: verified via a harness compiled directly against
  `VideoImportService.swift` using `ffmpeg`-generated sample files — correct dimensions,
  managed-storage copy, and thumbnail generation all confirmed.
- **Reject unreadable/non-video input**: a `.mp4`-named text file was correctly rejected
  with an AVFoundation-backed error.
- **Library persistence across restart**: two separate `JSONWallpaperRepository` instances
  over the same file (simulating app restart) — favorite flags, collections, display
  assignments, and playback settings all round-tripped correctly.
- **Assign the same video to two displays**: verified at the repository/persistence layer
  with two synthetic display IDs.
- **Steam Workshop scan/import/rescan**: a synthetic `steamapps/workshop/content/431960`
  tree with one video item (`project.json` type `video`) and one scene item (type `scene`)
  was scanned — the video item was correctly marked ready-to-import and the scene item
  unsupported (and never unpacked/executed). The video item was imported, confirmed
  byte-identical to the untouched source file, and a rescan correctly detected it as a
  duplicate by fingerprint rather than copying it again.
- **Desktop playback start-up**: the compiled app was launched with a seeded library and
  display assignment; `CGWindowListCopyWindowInfo` confirmed a window was created at
  exactly `CGWindowLevelForKey(.desktopIconWindow) - 1` with full-screen bounds — i.e. the
  intended "behind Finder icons" placement — and that playback resumed automatically from
  persisted state without user interaction, as intended.
- **Search / favorite / UI flows**: covered by code review and the type-checked SwiftUI
  view hierarchy, since this sandboxed environment has no Screen Recording/Accessibility
  permission available for pixel-level screenshot verification (see
  `docs/ARCHITECTURE.md`'s limitations section).

**Not verified**: real multiple-monitor hardware (only one physical display was available)
and experimental Lock Screen playback (not implemented — intentionally always reports
unavailable).

## Side effect during testing, now reverted

While testing Desktop playback, this session's test run set the real system Desktop
picture (via the same `NSWorkspace.setDesktopImageURL` call the app uses) to a generated
poster frame from a test video. This was reset back to a stock macOS default
(`Sonoma.heic`) before finishing, since no prior custom wallpaper could be recovered from
this environment (no desktop-picture history/preference file was present to restore from,
consistent with this being a fresh environment). Worth knowing in case the desktop picture
on this machine looks different than expected.

## Next steps if continuing this project

1. Build and run on a machine with full Xcode to get a true `xcodebuild` pass and exercise
   the app visually.
2. Validate on real multiple displays (connect/disconnect behavior, independent vs.
   synced-rotation assignment, Spaces/Mission Control/fullscreen interaction).
3. If Apple ever ships a public API for animated Lock Screen wallpaper, implement it as a
   normal (non-experimental) adapter — the `LockScreenAdapter` module is already isolated
   so this would be a contained change.
4. If Steamworks authorization for a suitable App ID is obtained, a real in-app
   subscribe/download integration could be added as a separate, explicitly-authorized
   module — current behavior (open Steam's pages, import what's already downloaded) should
   remain the default regardless.

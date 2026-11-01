# Luma

Luma is a native, video-only macOS wallpaper app. It imports your own MP4/MOV files and
Steam Workshop videos you've already downloaded through Steam, organizes them in one dark
SwiftUI library, and plays them as an animated Desktop background through an app-managed
window — macOS has no public API to set a video as the actual Desktop picture, so Luma
provides the closest supported equivalent and is explicit about what that technique can and
can't guarantee. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full breakdown of
what's genuinely supported versus experimental, and [CONTEXT.md](CONTEXT.md) for current
implementation status.

## Requirements

- macOS 14 (Sonoma) or later to run.
- Xcode 15+ to build and run the `.xcodeproj` target (recommended — this is the real app
  target with its icon and Info.plist).
- Swift 5.9+ command-line tools are enough to build the Swift package target, if you don't
  have Xcode installed. This was the only toolchain available while building this project,
  so the Swift package path is the one that's actually been built and run here; the
  `.xcodeproj` could not be compiled on this machine (see the note below).

## Build & run — Xcode (recommended)

```sh
open Luma.xcodeproj
```

Select the **Luma** scheme and Run. The project is generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) from [project.yml](project.yml); if you
change the file layout, regenerate with:

```sh
xcodegen generate --spec project.yml
```

## Build & run — Swift Package (no Xcode required)

```sh
swift build
swift run
```

This produces a bare executable (no app icon/bundle metadata, since SwiftPM executables
aren't `.app` bundles), but it's the same source and the same behavior.

> **Note on this machine:** the environment this project was built in has Xcode's Command
> Line Tools but not the Xcode.app bundle, so `xcodebuild` isn't available here and the
> `.xcodeproj` build could not be run end-to-end on this machine. `swift build` was
> verified repeatedly against the exact same source files and completes with no errors or
> warnings beyond two pre-existing linker search-path warnings caused by the missing
> Xcode.app Developer directory (unrelated to this app's code). If you build on a machine
> with Xcode installed, `xcodebuild -scheme Luma -project Luma.xcodeproj build` should be
> used to confirm the app target too.

## What's real vs. experimental

- **Desktop video wallpaper** is implemented and works: an app-owned, click-through window
  per display, placed just behind the Desktop icon layer, rendering through
  `AVPlayerItemVideoOutput` with a genuine frame-rate cap (not just a label on a setting).
- **Lock Screen video wallpaper is not implemented and is not claimed to work.** There is no
  public macOS API for it. The Lock Screen toggle in Settings only runs a diagnostic check
  and always reports itself as unavailable — see `Sources/Luma/LockScreen/`.
- **Steam Workshop** discovery opens Steam's own pages; Luma never signs in to Steam or
  calls any Steamworks API. It only scans a folder you point it at and copies videos that
  AVFoundation can actually decode.

## Project layout

```text
Luma.xcodeproj/     Generated Xcode project (via XcodeGen + project.yml)
Package.swift        Swift Package manifest (same sources, buildable without Xcode)
Sources/Luma/         All application code — see docs/ARCHITECTURE.md for the module map
Resources/            Info.plist and app icon asset catalog for the Xcode target
docs/ARCHITECTURE.md  Final architecture, API boundaries, and known limitations
CONTEXT.md            Current implementation state and verification notes
```

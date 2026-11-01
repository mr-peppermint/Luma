import AVFoundation
import AppKit

/// Generates and caches a full-resolution still frame from a video, for use as the system
/// desktop picture (`NSWorkspace.setDesktopImageURL`) when Luma's animated window isn't
/// covering the desktop — e.g. right before animated playback starts, or after it stops.
/// This is a real still image set through the one public API macOS offers for the desktop
/// picture; it is not a substitute for animated playback, which this app provides via its
/// own window instead.
actor DesktopPosterGenerator {
    static let shared = DesktopPosterGenerator()

    private var cache: [UUID: URL] = [:]

    func posterURL(for wallpaper: VideoWallpaper) async -> URL? {
        if let cached = cache[wallpaper.id], FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        guard let generated = try? await generate(for: wallpaper) else { return nil }
        cache[wallpaper.id] = generated
        return generated
    }

    private func generate(for wallpaper: VideoWallpaper) async throws -> URL {
        let asset = AVURLAsset(url: wallpaper.fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 3840, height: 2160)

        let duration = try await asset.load(.duration)
        let midpoint = CMTime(seconds: min(1.0, duration.seconds / 2), preferredTimescale: 600)
        let cgImage = try await generator.image(at: midpoint).image

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw VideoImportError.unreadable("could not encode poster image")
        }

        let directory = try VideoImportService.managedRoot().appendingPathComponent("Posters", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(wallpaper.id.uuidString).png")
        try data.write(to: url, options: .atomic)
        return url
    }
}

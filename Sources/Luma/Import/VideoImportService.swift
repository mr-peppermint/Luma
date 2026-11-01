import AppKit
import AVFoundation
import CryptoKit
import Foundation

enum VideoImportError: LocalizedError {
    case unsupportedExtension
    case noVideoTrack
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedExtension:
            return "Choose an MP4 or MOV video."
        case .noVideoTrack:
            return "This file could not be read as a video by AVFoundation."
        case .unreadable(let reason):
            return "AVFoundation could not read this file: \(reason)"
        }
    }
}

/// Validates and copies MP4/MOV files into Luma's managed media folder. Also used by the
/// Workshop importer, since both paths share the same "is this actually a readable video"
/// gate and the same managed-storage layout.
actor VideoImportService {
    static let supportedExtensions: Set<String> = ["mp4", "mov"]

    private let fileManager = FileManager.default

    func importVideo(from sourceURL: URL) async throws -> VideoWallpaper {
        let ext = sourceURL.pathExtension.lowercased()
        guard Self.supportedExtensions.contains(ext) else { throw VideoImportError.unsupportedExtension }

        let hasAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let probe = try await Self.probe(url: sourceURL)
        let destinationDirectory = try Self.managedVideoDirectory()
        let destinationURL = Self.uniqueDestination(for: sourceURL, in: destinationDirectory)
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let thumbnailURL = try? await Self.generateThumbnail(for: destinationURL)

        return VideoWallpaper(
            title: sourceURL.deletingPathExtension().lastPathComponent,
            fileURL: destinationURL,
            thumbnailURL: thumbnailURL,
            durationSeconds: probe.duration,
            pixelWidth: probe.width,
            pixelHeight: probe.height
        )
    }

    struct Probe {
        var duration: Double?
        var width: Int?
        var height: Int?
    }

    /// Confirms AVFoundation can actually decode this as a video (not just that the extension
    /// looks right) and returns the metadata every importer needs.
    static func probe(url: URL) async throws -> Probe {
        let asset = AVURLAsset(url: url)
        do {
            let isPlayable = try await asset.load(.isPlayable)
            guard isPlayable else { throw VideoImportError.unreadable("asset reported not playable") }
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw VideoImportError.noVideoTrack }
            let duration = try await asset.load(.duration).seconds
            let size = try await track.load(.naturalSize)
            return Probe(
                duration: duration.isFinite ? duration : nil,
                width: Int(abs(size.width)),
                height: Int(abs(size.height))
            )
        } catch let error as VideoImportError {
            throw error
        } catch {
            throw VideoImportError.unreadable(error.localizedDescription)
        }
    }

    static func managedVideoDirectory() throws -> URL {
        let directory = try managedRoot().appendingPathComponent("Videos", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func managedThumbnailDirectory() throws -> URL {
        let directory = try managedRoot().appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func managedRoot() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Luma", isDirectory: true)
    }

    static func uniqueDestination(for source: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        var target = directory.appendingPathComponent(source.lastPathComponent)
        var suffix = 2
        while fileManager.fileExists(atPath: target.path) {
            let name = source.deletingPathExtension().lastPathComponent
            target = directory.appendingPathComponent("\(name) \(suffix).\(source.pathExtension)")
            suffix += 1
        }
        return target
    }

    @discardableResult
    static func generateThumbnail(for videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 270)

        let duration = try await asset.load(.duration)
        let midpoint = CMTime(seconds: min(1.0, duration.seconds / 2), preferredTimescale: 600)
        let cgImage = try await generator.image(at: midpoint).image

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw VideoImportError.unreadable("could not encode thumbnail")
        }
        let directory = try managedThumbnailDirectory()
        let thumbnailURL = directory.appendingPathComponent(videoURL.deletingPathExtension().lastPathComponent + ".png")
        try data.write(to: thumbnailURL, options: .atomic)
        return thumbnailURL
    }

    /// A cheap, stable fingerprint (not a full content hash) used to detect the same Workshop
    /// file across repeat scans without reading the entire video every time.
    static func fileFingerprint(for url: URL) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        var hasher = SHA256()
        hasher.update(data: Data(url.path.utf8))
        withUnsafeBytes(of: size) { hasher.update(bufferPointer: $0) }
        withUnsafeBytes(of: modified) { hasher.update(bufferPointer: $0) }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

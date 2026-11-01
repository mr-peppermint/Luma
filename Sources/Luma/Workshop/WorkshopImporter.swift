import Foundation

/// Copies one user-selected Workshop video into Luma's managed media folder. Never edits
/// or deletes anything under the Steam folder — it only reads the source file once, to
/// copy it and to probe it with AVFoundation.
actor WorkshopImporter {
    func importCandidate(
        videoURL: URL,
        workshopID: String,
        title: String,
        sourceFolderPath: String
    ) async throws -> VideoWallpaper {
        let probe = try await VideoImportService.probe(url: videoURL)
        let fingerprint = try VideoImportService.fileFingerprint(for: videoURL)

        let destinationDirectory = try VideoImportService.managedVideoDirectory()
        let destinationURL = VideoImportService.uniqueDestination(for: videoURL, in: destinationDirectory)
        try FileManager.default.copyItem(at: videoURL, to: destinationURL)

        let thumbnailURL = try? await VideoImportService.generateThumbnail(for: destinationURL)

        return VideoWallpaper(
            title: title,
            fileURL: destinationURL,
            thumbnailURL: thumbnailURL,
            origin: .steamWorkshop,
            durationSeconds: probe.duration,
            pixelWidth: probe.width,
            pixelHeight: probe.height,
            workshopInfo: WorkshopProvenance(
                workshopID: workshopID,
                sourceFolderPath: sourceFolderPath,
                sourceFileFingerprint: fingerprint
            )
        )
    }

    /// Fingerprint of a would-be import, so callers can check for duplicates before copying.
    func fingerprint(for videoURL: URL) throws -> String {
        try VideoImportService.fileFingerprint(for: videoURL)
    }
}

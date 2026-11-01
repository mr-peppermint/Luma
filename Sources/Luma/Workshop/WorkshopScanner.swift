import AVFoundation
import Foundation

/// Read-only scanner over a user-selected Steam/Workshop folder. It never writes, never
/// extracts archives, never executes anything it finds, and never follows a symlink that
/// would lead outside the item folder being scanned. It only identifies candidate video
/// files and lets AVFoundation confirm they decode as video.
actor WorkshopScanner {
    struct Progress: Sendable {
        var scanned: Int
        var total: Int
    }

    private let fileManager = FileManager.default
    private let maxTraversalDepth = 3
    private let videoExtensions = VideoImportService.supportedExtensions
    private let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif"]

    /// Resolves the given root to an items directory (a folder whose immediate children
    /// are one Workshop item each) and scans every child. Accepts either the Workshop
    /// content folder itself, a Steam library root that contains it, or a folder the user
    /// pointed at directly that already looks like an items directory.
    func scan(root: URL, onProgress: (@Sendable (Progress) async -> Void)? = nil) async -> [WorkshopScanResult] {
        guard let itemsRoot = resolveItemsRoot(from: root) else { return [] }
        guard let itemFolders = try? fileManager.contentsOfDirectory(
            at: itemsRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let directories = itemFolders.filter { isPlainDirectory($0) }
        var results: [WorkshopScanResult] = []
        for (index, folder) in directories.enumerated() {
            if let result = await scanItemFolder(folder) {
                results.append(result)
            }
            await onProgress?(Progress(scanned: index + 1, total: directories.count))
        }
        return results.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func resolveItemsRoot(from root: URL) -> URL? {
        if root.lastPathComponent == wallpaperEngineWorkshopAppID, isPlainDirectory(root) {
            return root
        }
        let nestedCandidates = [
            root.appendingPathComponent("steamapps/workshop/content/\(wallpaperEngineWorkshopAppID)"),
            root.appendingPathComponent("workshop/content/\(wallpaperEngineWorkshopAppID)"),
            root.appendingPathComponent("content/\(wallpaperEngineWorkshopAppID)"),
        ]
        if let found = nestedCandidates.first(where: isPlainDirectory) {
            return found
        }
        // The user may have pointed directly at a folder of item subfolders.
        if isPlainDirectory(root) { return root }
        return nil
    }

    private func scanItemFolder(_ folder: URL) async -> WorkshopScanResult? {
        let workshopID = folder.lastPathComponent
        let entries = safeEnumerate(root: folder, depth: maxTraversalDepth)

        let metadata = readProjectMetadata(in: folder)
        let declaredKind = WorkshopItemKind(projectType: metadata?.type)

        var videoCandidates: [URL] = []
        var imageCandidates: [URL] = []
        var totalSize: Int64 = 0

        for entry in entries {
            totalSize += fileSize(entry)
            let ext = entry.pathExtension.lowercased()
            if videoExtensions.contains(ext) {
                videoCandidates.append(entry)
            } else if imageExtensions.contains(ext) {
                imageCandidates.append(entry)
            }
        }

        // If project.json names a specific file, prefer it as the sole candidate when it exists.
        if let namedFile = metadata?.file, !namedFile.isEmpty {
            let namedURL = folder.appendingPathComponent(namedFile)
            let ext = namedURL.pathExtension.lowercased()
            if videoExtensions.contains(ext), fileManager.fileExists(atPath: namedURL.path) {
                videoCandidates = [namedURL] + videoCandidates.filter { $0 != namedURL }
            }
        }

        let title = metadata?.title ?? workshopID
        let previewURL = metadata?.preview.flatMap { name -> URL? in
            let url = folder.appendingPathComponent(name)
            return fileManager.fileExists(atPath: url.path) ? url : nil
        } ?? imageCandidates.first

        let status = await determineStatus(
            declaredKind: declaredKind,
            videoCandidates: videoCandidates
        )

        return WorkshopScanResult(
            workshopID: workshopID,
            folderURL: folder,
            title: title,
            declaredKind: declaredKind,
            candidateVideoFiles: videoCandidates,
            previewImageURL: previewURL,
            totalSizeBytes: totalSize,
            status: status
        )
    }

    private func determineStatus(declaredKind: WorkshopItemKind, videoCandidates: [URL]) async -> WorkshopItemStatus {
        switch declaredKind {
        case .scene:
            return .unsupported(reason: "Scene wallpapers are not supported — Luma only plays pre-rendered video.")
        case .web:
            return .unsupported(reason: "Web wallpapers are not supported — Luma only plays pre-rendered video.")
        case .application:
            return .unsupported(reason: "Application wallpapers are not supported.")
        case .video, .unknown:
            break
        }

        guard !videoCandidates.isEmpty else {
            return .unsupported(reason: "No MP4 or MOV file was found in this item's folder.")
        }

        for candidate in videoCandidates {
            if (try? await VideoImportService.probe(url: candidate)) != nil {
                return .readyToImport
            }
        }
        return .unsupported(reason: "AVFoundation could not read any video file in this item's folder.")
    }

    private func readProjectMetadata(in folder: URL) -> WorkshopProjectMetadata? {
        let url = folder.appendingPathComponent("project.json")
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WorkshopProjectMetadata.self, from: data)
    }

    /// Walks a directory tree up to `depth` levels, skipping symlinks that resolve outside
    /// `root`, and never opening or executing anything — only reading file-system metadata.
    private func safeEnumerate(root: URL, depth: Int) -> [URL] {
        guard let standardizedRoot = try? root.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath else {
            return enumerate(root, remainingDepth: depth, boundaryPath: root.standardizedFileURL.path)
        }
        return enumerate(root, remainingDepth: depth, boundaryPath: standardizedRoot)
    }

    private func enumerate(_ directory: URL, remainingDepth: Int, boundaryPath: String) -> [URL] {
        guard remainingDepth > 0 else { return [] }
        guard let children = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                guard let resolved = try? fileManager.destinationOfSymbolicLink(atPath: child.path) else { continue }
                let resolvedURL = URL(fileURLWithPath: resolved, relativeTo: child.deletingLastPathComponent()).standardizedFileURL
                guard resolvedURL.path.hasPrefix(boundaryPath) else { continue }
                continue // Never traverse through symlinks even when they resolve inside the root.
            }
            if values?.isDirectory == true {
                results.append(contentsOf: enumerate(child, remainingDepth: remainingDepth - 1, boundaryPath: boundaryPath))
            } else {
                results.append(child)
            }
        }
        return results
    }

    private func isPlainDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).flatMap { Int64($0) } ?? 0
    }
}

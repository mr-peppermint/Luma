import AppKit
import Foundation

/// Drives the Steam Workshop screen: choosing a folder, scanning it, resolving duplicates
/// against the library, disambiguating multi-candidate items, and importing.
@MainActor
final class WorkshopViewModel: ObservableObject {
    @Published var selectedRoot: URL?
    @Published var isShowingFolderPicker = false
    @Published var isScanning = false
    @Published var scanProgress: (scanned: Int, total: Int)?
    @Published var results: [WorkshopScanResult] = []
    @Published var importError: String?
    @Published var importingWorkshopID: String?

    /// When a scan result has more than one plausible video file, the UI asks the user to
    /// pick one before importing.
    @Published var pendingDisambiguation: WorkshopScanResult?

    private let env: AppEnvironment
    var onLibraryChanged: () async -> Void = {}

    init(env: AppEnvironment) {
        self.env = env
    }

    var detectedFolders: [URL] {
        env.steamLocator.likelyWorkshopContentFolders()
    }

    func openWorkshopInBrowser() {
        NSWorkspace.shared.open(SteamLinks.wallpaperEngineWorkshopURL)
    }

    func openItemInBrowser(workshopID: String) {
        guard let url = SteamLinks.workshopItemURL(id: workshopID) else { return }
        NSWorkspace.shared.open(url)
    }

    func chooseFolder(_ url: URL) {
        selectedRoot = url
        Task { await scan() }
    }

    func scan() async {
        guard let root = selectedRoot else { return }
        isScanning = true
        scanProgress = nil
        defer { isScanning = false }

        var scanned = await env.workshopScanner.scan(root: root) { [weak self] progress in
            await self?.updateScanProgress(progress)
        }
        await markDuplicates(&scanned)
        results = scanned
    }

    private func updateScanProgress(_ progress: WorkshopScanner.Progress) {
        scanProgress = (progress.scanned, progress.total)
    }

    private func markDuplicates(_ scanned: inout [WorkshopScanResult]) async {
        for index in scanned.indices {
            guard case .readyToImport = scanned[index].status,
                  let candidate = scanned[index].candidateVideoFiles.first else { continue }
            if let fingerprint = try? await env.workshopImporter.fingerprint(for: candidate),
               let alreadyPresent = try? await env.repository.fingerprintExists(fingerprint),
               alreadyPresent {
                scanned[index].status = .alreadyInLibrary
            }
        }
    }

    /// Imports the result's sole/first candidate, or if ambiguous, requests disambiguation
    /// via `pendingDisambiguation` instead of guessing.
    func importResult(_ result: WorkshopScanResult) {
        guard case .readyToImport = result.status else { return }
        if result.candidateVideoFiles.count > 1 {
            pendingDisambiguation = result
            return
        }
        guard let candidate = result.candidateVideoFiles.first else { return }
        performImport(result: result, candidate: candidate)
    }

    func resolveDisambiguation(result: WorkshopScanResult, chosen: URL) {
        pendingDisambiguation = nil
        performImport(result: result, candidate: chosen)
    }

    private func performImport(result: WorkshopScanResult, candidate: URL) {
        importingWorkshopID = result.workshopID
        Task {
            defer { importingWorkshopID = nil }
            do {
                let wallpaper = try await env.workshopImporter.importCandidate(
                    videoURL: candidate,
                    workshopID: result.workshopID,
                    title: result.title,
                    sourceFolderPath: result.folderURL.path
                )
                try await env.repository.add(wallpaper)
                if let index = results.firstIndex(where: { $0.workshopID == result.workshopID }) {
                    results[index].status = .alreadyInLibrary
                }
                await onLibraryChanged()
            } catch {
                importError = "\(result.title): \(error.localizedDescription)"
            }
        }
    }
}

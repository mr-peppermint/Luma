import SwiftUI

struct WorkshopView: View {
    @EnvironmentObject private var workshop: WorkshopViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    disclosureNote
                    actionsRow
                    if let folder = workshop.selectedRoot {
                        Text("Scanning: \(folder.path)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if workshop.isScanning {
                        progressRow
                    }
                    resultsList
                }
                .padding(28)
            }
        }
        .fileImporter(isPresented: $workshop.isShowingFolderPicker, allowedContentTypes: [.folder]) { result in
            if case let .success(url) = result {
                workshop.chooseFolder(url)
            }
        }
        .sheet(item: $workshop.pendingDisambiguation) { result in
            DisambiguationSheet(result: result)
        }
        .alert("Couldn't import item", isPresented: Binding(
            get: { workshop.importError != nil },
            set: { if !$0 { workshop.importError = nil } }
        )) {
            Button("OK", role: .cancel) { workshop.importError = nil }
        } message: {
            Text(workshop.importError ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Steam Workshop")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Text("Discover on Steam, then import videos Steam has already downloaded")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 16)
    }

    private var disclosureNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Theme.sectionHeader("HOW THIS WORKS")
            Text("Luma never signs in to Steam, never calls Wallpaper Engine's Workshop service, and never downloads anything itself. Subscribing and downloading happen entirely in Steam. Once a video Workshop item is on disk, Luma can scan the folder and copy the video into its own library.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 12) {
            Button {
                workshop.openWorkshopInBrowser()
            } label: {
                Label("Open Workshop", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button {
                workshop.isShowingFolderPicker = true
            } label: {
                Label("Choose Steam Folder", systemImage: "folder")
            }
            .buttonStyle(.bordered)

            if !workshop.detectedFolders.isEmpty {
                Menu("Detected Folders") {
                    ForEach(workshop.detectedFolders, id: \.self) { folder in
                        Button(folder.path) { workshop.chooseFolder(folder) }
                    }
                }
            }

            Button {
                Task { await workshop.scan() }
            } label: {
                Label("Scan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(workshop.selectedRoot == nil || workshop.isScanning)
        }
    }

    private var progressRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            if let progress = workshop.scanProgress {
                Text("Scanning item \(progress.scanned) of \(progress.total)…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Scanning…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var resultsList: some View {
        if workshop.results.isEmpty {
            if !workshop.isScanning, workshop.selectedRoot != nil {
                Text("No Workshop items found in this folder.")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(workshop.results) { result in
                    WorkshopResultRow(result: result)
                }
            }
        }
    }
}

private struct WorkshopResultRow: View {
    @EnvironmentObject private var workshop: WorkshopViewModel
    let result: WorkshopScanResult

    var body: some View {
        HStack(spacing: 14) {
            thumbnail
            VStack(alignment: .leading, spacing: 4) {
                Text(result.title).font(.system(size: 13, weight: .medium))
                Text("Workshop ID \(result.workshopID) · \(formattedSize(result.totalSizeBytes))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                statusLabel
            }
            Spacer()
            actionButton
        }
        .padding(12)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var thumbnail: some View {
        if let previewURL = result.previewImageURL, let image = NSImage(contentsOf: previewURL) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 64, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6)
                .fill(.white.opacity(0.08))
                .frame(width: 64, height: 40)
                .overlay(Image(systemName: "film").foregroundStyle(.secondary))
        }
    }

    @ViewBuilder private var statusLabel: some View {
        switch result.status {
        case .readyToImport:
            PillBadge(text: "READY TO IMPORT", tint: .green)
        case .alreadyInLibrary:
            PillBadge(text: "ALREADY IN LIBRARY", tint: .blue)
        case .unsupported(let reason):
            Text(reason)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch result.status {
        case .readyToImport:
            Button {
                workshop.importResult(result)
            } label: {
                if workshop.importingWorkshopID == result.workshopID {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Import")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(workshop.importingWorkshopID != nil)
        case .alreadyInLibrary:
            Button("View on Steam") { workshop.openItemInBrowser(workshopID: result.workshopID) }
                .buttonStyle(.bordered)
        case .unsupported:
            EmptyView()
        }
    }

    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct DisambiguationSheet: View {
    @EnvironmentObject private var workshop: WorkshopViewModel
    @Environment(\.dismiss) private var dismiss
    let result: WorkshopScanResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Multiple video files found")
                .font(.headline)
            Text("\(result.title) has more than one candidate video. Choose which one to import.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(result.candidateVideoFiles, id: \.self) { url in
                Button {
                    workshop.resolveDisambiguation(result: result, chosen: url)
                    dismiss()
                } label: {
                    Text(url.lastPathComponent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
            Button("Cancel", role: .cancel) { dismiss() }
        }
        .padding(24)
        .frame(minWidth: 420)
    }
}

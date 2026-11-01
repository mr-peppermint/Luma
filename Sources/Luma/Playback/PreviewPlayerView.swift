import AVKit
import SwiftUI

/// Small in-app preview player for the library/detail views. Desktop playback uses its own
/// renderer (`DesktopVideoView`) for click-through windowing and FPS capping; this one is a
/// plain `AVPlayerLayer`-backed preview with normal system video controls.
struct PreviewPlayerView: View {
    let url: URL
    @StateObject private var box: StateBox<AVPlayer>

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        _box = StateObject(wrappedValue: StateBox(player))
    }

    private var player: AVPlayer { box.value }

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.play() }
            .onDisappear { player.pause() }
            .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { _ in
                player.seek(to: .zero)
                player.play()
            }
    }
}

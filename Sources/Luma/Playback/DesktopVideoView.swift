import AppKit
import AVFoundation
import QuartzCore

/// Renders one looping, muted-by-default video into a desktop window. Uses
/// `AVPlayerItemVideoOutput` plus `NSView.displayLink(target:selector:)` (macOS 14+) rather
/// than a plain `AVPlayerLayer` so the frame-rate cap setting is a real throttle on how often
/// a new frame is pulled and drawn, not just a label — `CADisplayLink.preferredFrameRateRange`
/// tells the system the cadence we want, and the pull-and-draw step is skipped on ticks that
/// still land inside the previous frame's budget as a second line of defense.
final class DesktopVideoView: NSView {
    private let player: AVPlayer
    private var videoOutput: AVPlayerItemVideoOutput?
    private var frameTick: CADisplayLink?
    private let ciContext: CIContext
    private var endObserver: NSObjectProtocol?
    private let contentLayer = CALayer()
    private var lastDrawHostTime: CFTimeInterval = 0

    var fitMode: FitMode {
        didSet { updateGravity() }
    }

    var frameRateCap: FrameRateCap {
        didSet { applyFrameRateCap() }
    }

    var isPlaybackActive: Bool = true {
        didSet { if oldValue != isPlaybackActive { syncPlaybackState() } }
    }

    init(player: AVPlayer, fitMode: FitMode, frameRateCap: FrameRateCap, ciContext: CIContext) {
        self.player = player
        self.fitMode = fitMode
        self.frameRateCap = frameRateCap
        self.ciContext = ciContext
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        contentLayer.backgroundColor = NSColor.black.cgColor
        updateGravity()
        layer?.addSublayer(contentLayer)
        attachVideoOutput()
        observeLoop()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        frameTick?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let output = videoOutput, let item = player.currentItem {
            item.remove(output)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            frameTick?.invalidate()
            frameTick = nil
            return
        }
        guard frameTick == nil else { return }
        let link = displayLink(target: self, selector: #selector(step))
        link.add(to: .main, forMode: .common)
        frameTick = link
        applyFrameRateCap()
    }

    override func layout() {
        super.layout()
        contentLayer.frame = bounds
    }

    private func updateGravity() {
        contentLayer.contentsGravity = fitMode == .fill ? .resizeAspectFill : .resizeAspect
    }

    private func applyFrameRateCap() {
        guard let tick = frameTick else { return }
        if frameRateCap == .uncapped {
            tick.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 120, preferred: 60)
        } else {
            let fps = Float(frameRateCap.rawValue)
            tick.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        }
    }

    private func attachVideoOutput() {
        guard let item = player.currentItem else { return }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        videoOutput = output
    }

    private func observeLoop() {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            if self?.isPlaybackActive == true { self?.player.play() }
        }
    }

    @objc private func step(_ sender: CADisplayLink) {
        guard isPlaybackActive, let output = videoOutput else { return }

        if frameRateCap != .uncapped {
            let minInterval = 1.0 / Double(frameRateCap.rawValue)
            if lastDrawHostTime != 0, sender.targetTimestamp - lastDrawHostTime < minInterval {
                return
            }
        }

        let itemTime = output.itemTime(forHostTime: sender.targetTimestamp)
        guard output.hasNewPixelBuffer(forItemTime: itemTime),
              let pixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        lastDrawHostTime = sender.targetTimestamp
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.contents = cgImage
        CATransaction.commit()
    }

    private func syncPlaybackState() {
        if isPlaybackActive {
            player.play()
        } else {
            player.pause()
        }
    }
}

import SwiftUI
import AVFoundation
import DisplayCore

// A zero-chrome looping video layer. It uses AVPlayerLayer directly (not SwiftUI's VideoPlayer, which
// shows transport controls) so the art reaches the panel edges with no UI (§6). Seamless loop via
// AVPlayerLooper; Fit/Fill maps to the layer's videoGravity. Muted for now — the audio session and the
// per-display Sound setting arrive in C5.
struct VideoLayerView: UIViewRepresentable {
    let url: URL
    let fit: Fit

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView(url: url, fit: fit) }
    func updateUIView(_ uiView: PlayerUIView, context: Context) { uiView.update(url: url, fit: fit) }
    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) { uiView.teardown() }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL, fit: Fit) {
        super.init(frame: .zero)
        backgroundColor = .black
        update(url: url, fit: fit)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func update(url: URL, fit: Fit) {
        playerLayer.videoGravity = (fit == .fill) ? .resizeAspectFill : .resizeAspect
        guard url != currentURL else { return }
        currentURL = url
        teardown()
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)) // seamless loop
        player.isMuted = true
        playerLayer.player = player
        queue = player
        player.play()
    }

    func teardown() {
        queue?.pause()
        looper = nil
        queue = nil
        playerLayer.player = nil
    }
}

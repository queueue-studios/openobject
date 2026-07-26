import SwiftUI
import AVFoundation
import DisplayCore

// A zero-chrome looping video layer. It uses AVPlayerLayer directly (not SwiftUI's VideoPlayer, which
// shows transport controls) so the art reaches the panel edges with no UI (§6). Seamless loop via
// AVPlayerLooper; Fit/Fill maps to the layer's videoGravity. `muted` follows the app's Sound setting
// (§10); the app's audio session (OpenObjectTVApp) lets a scored video be heard when unmuted.
struct VideoLayerView: UIViewRepresentable {
    let url: URL
    let fit: Fit
    let muted: Bool

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView(url: url, fit: fit, muted: muted) }
    func updateUIView(_ uiView: PlayerUIView, context: Context) { uiView.update(url: url, fit: fit, muted: muted) }
    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) { uiView.teardown() }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    init(url: URL, fit: Fit, muted: Bool) {
        super.init(frame: .zero)
        backgroundColor = .black
        update(url: url, fit: fit, muted: muted)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func update(url: URL, fit: Fit, muted: Bool) {
        playerLayer.videoGravity = (fit == .fill) ? .resizeAspectFill : .resizeAspect
        queue?.isMuted = muted   // live mute change even when the same clip keeps playing
        guard url != currentURL else { return }
        currentURL = url
        teardown()
        // Activate the playback session now that real video audio may play (§10); harmless when muted.
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVQueuePlayer()
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url)) // seamless loop
        player.isMuted = muted
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

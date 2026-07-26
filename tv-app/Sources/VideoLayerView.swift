import SwiftUI
import AVFoundation
import DisplayCore

// Keeps exactly one piece audible across a crossfade (§10). The stage calls `silenceCurrent()` the moment
// the next piece takes over, so the OUTGOING video goes quiet immediately instead of bleeding through the
// 0.6s fade and on into the next piece: its AVPlayer otherwise keeps playing (and sounding) until SwiftUI
// removes the view, which was the "previous piece's audio keeps playing over the new one" bug.
@MainActor
final class AudioBus {
    private weak var current: PlayerUIView?

    /// The video now on screen registers itself as the audio owner.
    func register(_ player: PlayerUIView) { current = player }

    /// Mute whoever owns the stage right now. Called at each crossfade, before the next piece is audible.
    func silenceCurrent() {
        current?.forceMute()
        current = nil
    }

    /// A departing player relinquishes the bus if it still held it.
    func resign(_ player: PlayerUIView) {
        if current === player { current = nil }
    }
}

// A zero-chrome looping video layer. It uses AVPlayerLayer directly (not SwiftUI's VideoPlayer, which
// shows transport controls) so the art reaches the panel edges with no UI (§6). Seamless loop via
// AVPlayerLooper; Fit/Fill maps to the layer's videoGravity. `muted` follows the app's Sound setting
// (§10); the app's audio session (OpenObjectTVApp) lets a scored video be heard when unmuted.
struct VideoLayerView: UIViewRepresentable {
    let url: URL
    let fit: Fit
    let muted: Bool
    let bus: AudioBus

    func makeUIView(context: Context) -> PlayerUIView { PlayerUIView(url: url, fit: fit, muted: muted, bus: bus) }
    func updateUIView(_ uiView: PlayerUIView, context: Context) { uiView.update(url: url, fit: fit, muted: muted) }
    static func dismantleUIView(_ uiView: PlayerUIView, coordinator: ()) { uiView.dismantle() }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    private var queue: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private let bus: AudioBus

    init(url: URL, fit: Fit, muted: Bool, bus: AudioBus) {
        self.bus = bus
        super.init(frame: .zero)
        backgroundColor = .black
        update(url: url, fit: fit, muted: muted)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func update(url: URL, fit: Fit, muted: Bool) {
        playerLayer.videoGravity = (fit == .fill) ? .resizeAspectFill : .resizeAspect
        queue?.isMuted = muted   // live mute change even when the same clip keeps playing
        if url != currentURL {
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
        bus.register(self)   // this is the on-screen video; the stage silences it at the next crossfade
    }

    /// Cut this player's audio at once (the stage is crossfading to the next piece).
    func forceMute() { queue?.isMuted = true }

    /// Called when SwiftUI removes the view. Relinquish the bus, then stop and release the player so a
    /// looping clip cannot keep sounding after it leaves the stage.
    func dismantle() {
        bus.resign(self)
        teardown()
    }

    private func teardown() {
        queue?.pause()
        looper = nil
        queue = nil
        playerLayer.player = nil
    }
}

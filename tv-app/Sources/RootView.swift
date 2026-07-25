import SwiftUI
import DisplayCore

// Root of the tvOS app. C3 wires the RotationPlayer + MediaPipeline into the art stage and points them
// at a Host from the OO_HOST environment variable (a temporary stopgap: the real Host picker + manual
// entry + remembered default Host arrive in C4). Until a Host is set it shows the idle splash.
struct RootView: View {
    @State private var model = StageModel()

    var body: some View {
        Group {
            if let host = model.host {
                ArtStageView(player: model.player, host: host, pipeline: model.pipeline)
            } else {
                IdleSplashView()
            }
        }
        .ignoresSafeArea()
        .onAppear { model.startFromEnvironment() }
    }
}

@MainActor
@Observable
final class StageModel {
    let player: RotationPlayer
    let pipeline: MediaPipeline
    private(set) var host: Host?

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let cache = MediaCache(directory: caches.appendingPathComponent("OOMedia"))
        // A 4K Apple TV panel is 3840x2160; decode stills/frames to that longest side (§9). Tuned to the
        // real screen in a later refinement.
        pipeline = MediaPipeline(cache: cache, maxPixel: 3840)
        player = RotationPlayer()
    }

    // C3 stopgap: point at OO_HOST (e.g. http://192.168.1.42:3010). The Host picker (C4) replaces this.
    func startFromEnvironment() {
        guard host == nil,
              let raw = ProcessInfo.processInfo.environment["OO_HOST"],
              let resolved = Host.manualEntry(raw) else { return }
        host = resolved
        player.start(host: resolved)
    }
}

import SwiftUI
import AVFoundation

// OpenObject Apple TV app — entry point (TVOS-APP-PLAN §14 Phase C).
//
// A thin tvOS shell over the shared DisplayCore engine (../display-core). It takes exactly one role,
// Display (§3): it finds a Host on the LAN, the owner picks one, and it renders that Host's rotation full
// screen with zero chrome. It runs no server and owns no art.
@main
struct OpenObjectTVApp: App {
    init() {
        // A media-playback audio session so a scored video's sound can play (§10). Category only here; a
        // playing video activates the session (VideoLayerView), so background audio is not interrupted at
        // launch. Best-effort: audio is never on the critical path.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

import SwiftUI
import AVFoundation

// OpenObject iPad + iPhone app — entry point (TVOS-APP-PLAN §14 Phase G).
//
// A thin Universal touch shell over the shared DisplayCore engine and DisplayUI stage. It takes exactly
// one role, Display (§3): it finds a Host on the LAN, the owner picks one, and it renders that Host's
// rotation full-screen with zero chrome. It runs no server and owns no art. G1 is the buildable
// skeleton; the Host picker and art stage arrive in later Phase G checkpoints.
@main
struct OpenObjectApp: App {
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

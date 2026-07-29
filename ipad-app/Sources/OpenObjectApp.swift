import SwiftUI
import AVFoundation

// OpenObject iPad + iPhone app — entry point (TVOS-APP-PLAN §14 Phase G).
//
// A thin Universal touch shell over the shared DisplayCore engine and DisplayUI stage. It takes exactly
// one role, Display (§3): it finds a Host on the LAN, the owner picks one, and it renders that Host's
// rotation full-screen with zero chrome. It runs no server and owns no art. Both screens follow the
// device orientation (no landscape lock; Info.plist declares every orientation the app can use).
@main
struct OpenObjectApp: App {
    init() {
        // A media-playback audio session so a scored video's sound can play (§10). Category only here; a
        // playing video activates the session (VideoLayerView). Best-effort: audio is never critical-path.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Always-dark art UI: a black stage plus light-on-black chrome, regardless of the device's
                // Light/Dark setting. Without this, appearance-relative colors (.secondary) resolve to a
                // DARK gray in Light mode and nearly vanish on our black background.
                .preferredColorScheme(.dark)
        }
    }
}

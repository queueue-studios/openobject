import SwiftUI

// OpenObject Mac app — entry point (MAC-APP-PLAN §B1; HANDOFF §20, 2026-07-01).
//
// The native Swift shell around the shared engine (player/). Per the plan the app has BOTH a Dock
// presence (so it's a normal, discoverable app) AND a menu-bar item (for quick start/stop and
// opening the control panel / display). This B1a skeleton stands up exactly that dual presence and
// nothing more: no bundled Node, no server, no discovery yet. Those arrive in later checkpoints
// (B1b bundle the engine, B2 spawn the Host, B3 discovery, B4 drive Chrome, B5 the real menu UX).

@main
struct OpenObjectApp: App {
    var body: some Scene {
        // A normal window → gives the app its Dock icon. Clicking the Dock icon shows this window.
        WindowGroup("OpenObject") {
            ContentView()
        }
        .windowResizability(.contentSize)

        // The menu-bar item. Its menu is a placeholder for now; the real start/stop, open control
        // panel, open display, and Host/Display status actions land in B5.
        MenuBarExtra("OpenObject", systemImage: "photo") {
            MenuBarContent()
        }
    }
}

import SwiftUI

// OpenObject Mac app — entry point (MAC-APP-PLAN §B1; HANDOFF §20, 2026-07-01).
//
// The native Swift shell around the shared engine (player/). Per the plan the app has BOTH a Dock
// presence (a normal, discoverable app) AND a menu-bar item (quick start/stop, open control panel /
// display). An NSApplicationDelegate (below) owns the bundled engine's process lifecycle — started
// on launch, stopped cleanly on quit — and its EngineHost is shared into both scenes so the window
// and the menu bar reflect the same Host state.

@main
struct OpenObjectApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // A normal window → gives the app its Dock icon. Clicking the Dock icon shows this window.
        WindowGroup("OpenObject") {
            ContentView()
                .environmentObject(appDelegate.engine)
                .environmentObject(appDelegate.discovery)
                .environmentObject(appDelegate.roleStore)
        }
        // The window sizes exactly to its content: compact for a Host or two, taller for several,
        // and the list caps + scrolls beyond that (so the window never runs off-screen).
        .windowResizability(.contentSize)

        // The menu-bar item. Fuller start/stop, open control panel/display, and role/status UX
        // arrive in B5; for now it mirrors the Host status and offers Open Control Panel + Quit.
        MenuBarExtra("OpenObject", systemImage: "photo") {
            MenuBarContent()
                .environmentObject(appDelegate.engine)
        }
    }
}

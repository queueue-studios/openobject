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
                .environmentObject(appDelegate.display)
                .environmentObject(appDelegate.actions)
        }
        // The window sizes exactly to its content: compact for a Host or two, taller for several,
        // and the list caps + scrolls beyond that (so the window never runs off-screen).
        .windowResizability(.contentSize)
        // The same display controls in the standard top-left app menu (a "Display" menu), where Mac
        // users expect app controls — available whenever OpenObject is the active app. (Inside the
        // full-screen Chrome kiosk the top-left menu is Chrome's, so the menu-bar icon below is the
        // reachable copy there.)
        .commands {
            DisplayCommands(display: appDelegate.display, actions: appDelegate.actions)
        }

        // The menu-bar item — the display's remote, reachable even from inside the full-screen kiosk
        // (hover the top of the screen). Carries Return to Display / Show OpenObject / Stop, etc.
        MenuBarExtra("OpenObject", image: "MenuBarIcon") {
            MenuBarContent()
                .environmentObject(appDelegate.engine)
                .environmentObject(appDelegate.roleStore)
                .environmentObject(appDelegate.display)
                .environmentObject(appDelegate.actions)
        }
    }
}

// The top-left "Display" menu (shown when OpenObject is the active app). Mirrors the display controls
// so they're where Mac users look for app menus; reactive to the running state via @ObservedObject.
struct DisplayCommands: Commands {
    @ObservedObject var display: DisplayController
    let actions: DisplayActions

    var body: some Commands {
        CommandMenu("Display") {
            // Stable menu: items are always present and grayed out when they don't apply to the
            // current state (the macOS convention), rather than appearing/disappearing.
            Button("Open Display") { actions.openDisplay() }
                .disabled(!display.isChromeInstalled || display.state == .running)
            Button("Return to Display") { actions.returnToDisplay() }
                .disabled(display.state != .running)
            Button("Stop Display") { actions.stopDisplay() }
                .disabled(display.state != .running)
            Button("Open Control Panel") { actions.openControlPanel() }
        }
    }
}

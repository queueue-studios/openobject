import Foundation
import AppKit

// Shared actions for BOTH the window and the menu bar, so they drive identical behavior without
// duplicating the Host-vs-Viewer URL logic (MAC-APP-PLAN §B4/§B5). The menu bar matters because it
// is reachable from inside the full-screen Chrome kiosk (hover the top of the screen), so it is the
// display's escape hatch — "Return to Display", "Show OpenObject", "Stop Display" all live there.
@MainActor
final class DisplayActions: ObservableObject {
    private let engine: EngineHost
    private let discovery: HostDiscovery
    private let roleStore: RoleStore
    let display: DisplayController

    init(engine: EngineHost, discovery: HostDiscovery, roleStore: RoleStore, display: DisplayController) {
        self.engine = engine
        self.discovery = discovery
        self.roleStore = roleStore
        self.display = display
    }

    // Open the active Host's control panel in the default browser.
    func openControlPanel() {
        resolveActiveBase { base in NSWorkspace.shared.open(base) }
    }

    // Open the active Host's /display in a full-screen Chrome kiosk. Auto Display passes
    // `pinToPrimaryScreen` so the art lands on the one screen it has not blacked out (HANDOFF §17).
    func openDisplay(pinToPrimaryScreen: Bool = false) {
        let display = self.display
        resolveActiveBase { base in
            display.show(url: base.appendingPathComponent("display"), pinToPrimaryScreen: pinToPrimaryScreen)
        }
    }

    func stopDisplay() { display.stop() }

    // Bring the running kiosk back to the front (it lives on its own macOS Space).
    func returnToDisplay() { display.focusDisplay() }

    // Bring this app's control window to the front — e.g. from inside the full-screen display.
    func showControls() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
    }

    // Resolve the currently-active Host's base URL (Host = localhost; Viewer = the chosen remote,
    // resolved from Bonjour to host:port), then run `action`. Viewer resolution is async.
    private func resolveActiveBase(_ action: @escaping (URL) -> Void) {
        switch roleStore.mode {
        case .host:
            action(engine.baseURL)
        case .viewer(let id, _):
            guard let host = discovery.hosts.first(where: { $0.id == id }) else { return }
            Task {
                if let base = await discovery.resolveURL(for: host) { action(base) }
            }
        }
    }
}

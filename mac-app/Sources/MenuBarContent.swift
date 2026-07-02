import SwiftUI
import AppKit

// The menu-bar item's menu (B1a placeholder). The real actions — start/stop the Host, open the
// control panel, open the display, show whether this Mac is a Host or a Display and which server —
// arrive in B5. For now it just names the app and offers Quit, so the dual Dock + menu-bar
// presence is real and testable.
struct MenuBarContent: View {
    var body: some View {
        Text("OpenObject")
        Divider()
        Button("Quit OpenObject") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

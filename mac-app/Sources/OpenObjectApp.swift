import SwiftUI
import Sparkle

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
    @StateObject private var updater = UpdaterViewModel()

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
            // Sparkle's "Check for Updates…" in the standard spot, just under "About OpenObject".
            CommandGroup(after: .appInfo) {
                // Present but grayed out in Debug (where the updater is off), matching the stable-menu
                // convention the Display menu above already follows.
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.isEnabled)
            }
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

        // Preferences (app menu → Settings…, Cmd-comma): the Dock app icon.
        Settings {
            AppIconSettings()
        }
    }
}

// Settings pane: the Dock icon, and Auto Display's inactivity interval.
//
// Deliberately ONE pane, not tabs. An earlier note here anticipated moving to a tabbed Settings window
// as soon as a second setting arrived; two settings do not justify that (it would feel emptier and cost
// more clicks than a single pane). Revisit at five or six. (Matt, 2026-08-02; HANDOFF §17.)
struct AppIconSettings: View {
    @AppStorage(AppIcon.key) private var iconStyle = AppIcon.white.rawValue
    @AppStorage(AutoDisplayInterval.key) private var autoSeconds = AutoDisplayInterval.never.rawValue
    @State private var displaySleepMinutes: Int?

    // The chosen interval loses the race when macOS would blank the screen first (HANDOFF §17).
    private var losesToDisplaySleep: Bool {
        guard let sleep = displaySleepMinutes,
              let choice = AutoDisplayInterval(rawValue: autoSeconds), choice != .never
        else { return false }
        return choice.minutes >= sleep
    }

    var body: some View {
        Form {
            Picker("Dock icon", selection: $iconStyle) {
                Text("Auto").tag(AppIcon.auto.rawValue)
                Text("Light").tag(AppIcon.white.rawValue)
                Text("Dark").tag(AppIcon.black.rawValue)
            }
            .pickerStyle(.radioGroup)
            .onChange(of: iconStyle) { AppIcon.apply() }

            // Labeled with the feature's NAME, not a description of it, mirroring Apple's own control
            // (System Settings > Wallpaper > "Start Screen Saver", whose values carry the interval).
            // That keeps the name the docs and Help use visible in the UI, and matches the noun-label
            // form of the Dock icon row above. The row reads "Auto Display: After 10 minutes".
            Picker("Auto Display", selection: $autoSeconds) {
                ForEach(AutoDisplayInterval.menuOrder) { Text($0.label).tag($0.rawValue) }
            }

            // An always-visible caption under the control, which is what System Settings itself does
            // under nearly every row: convention, not added hint text. "Works like a screen saver" is
            // the fastest mental model there is, used as a simile while the feature keeps its own name
            // (it is not one, and does not appear in the System Settings screen saver list). "Inactive"
            // rather than "idle" to match Apple's own wording in the settings this sits beside.
            Text("Works like a screen saver, displaying your art full screen when your Mac has been "
                 + "inactive for a while. Press any key or move the pointer to return.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if losesToDisplaySleep, let sleep = displaySleepMinutes {
                Label(
                    "Your Mac turns its display off after \(sleep) minute\(sleep == 1 ? "" : "s"), "
                    + "so the screen goes dark before the art starts. Choose a shorter time here, or a "
                    + "longer one in System Settings > Lock Screen.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 430)
        .onAppear { displaySleepMinutes = AutoDisplayController.displaySleepMinutes() }
        .onChange(of: autoSeconds) { displaySleepMinutes = AutoDisplayController.displaySleepMinutes() }
    }
}

// Wraps Sparkle's updater so a SwiftUI menu item can trigger a check (MAC-APP-PLAN §C3). Sparkle reads
// SUFeedURL + SUPublicEDKey from Info.plist; startingUpdater:true begins Sparkle's automatic background
// checks (scheduled, with the user's consent prompt on first run).
//
// OFF IN DEBUG BUILDS. A local Debug build is ad-hoc signed (`CODE_SIGN_IDENTITY: "-"`), so when
// Sparkle's background check goes to touch an app bundle signed by the real team, macOS App Management
// blocks it and posts "OpenObject was prevented from modifying apps on your Mac". Nothing is broken:
// it is noise inherent to running an unsigned local build alongside an installed release, and it would
// invite someone to grant App Management rights to an unsigned binary, which they should not do.
// Release builds are unaffected, and provably so: `scripts/release.sh` builds `-configuration Release`,
// and SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG is set only on the Debug configuration.
final class UpdaterViewModel: ObservableObject {
    /// False in Debug builds, where the updater is never started and the menu item is disabled.
    let isEnabled: Bool
    private let controller: SPUStandardUpdaterController?

    init() {
        #if DEBUG
        isEnabled = false
        controller = nil
        #else
        isEnabled = true
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
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

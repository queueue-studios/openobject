import AppKit
import Combine

// The Dock icon can be white (default) or black, a runtime override via NSApp.applicationIconImage,
// persisted and re-applied on every launch. macOS does not round a runtime icon image, so
// DockIconWhite/DockIconBlack are pre-rounded copies of the app-icon masters. This affects only the
// Dock (and Cmd-Tab) while the app runs; the Finder/Launchpad icon stays the bundle's white icon.
enum AppIcon: String, CaseIterable {
    case auto, white, black
    static let key = "appIconStyle"
    static var current: AppIcon { AppIcon(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .white }

    // `auto` follows the system appearance: the dark icon in Dark Mode, the light icon in Light Mode.
    @MainActor private var imageName: String {
        switch self {
        case .white: return "DockIconWhite"
        case .black: return "DockIconBlack"
        case .auto:
            let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return dark ? "DockIconBlack" : "DockIconWhite"
        }
    }

    @MainActor static func apply(_ style: AppIcon = AppIcon.current) {
        UserDefaults.standard.set(style.rawValue, forKey: key)
        NSApp.applicationIconImage = NSImage(named: style.imageName)
    }
}

// Owns the app's long-lived objects and coordinates the engine's process lifecycle with the chosen
// role (MAC-APP-PLAN §B2/§B3). The local Host runs only in `.host` mode; in `.viewer` mode the app
// drives no server and instead points at a chosen remote Host. Using an NSApplicationDelegate gives
// reliable launch/terminate hooks, which matters for a child process.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = EngineHost()
    let discovery = HostDiscovery()
    let roleStore = RoleStore()
    let display = DisplayController()
    lazy var actions = DisplayActions(engine: engine, discovery: discovery, roleStore: roleStore, display: display)
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppIcon.apply()   // restore the chosen Dock icon (auto follows the system) before anything shows
        // Re-apply when the user flips Light/Dark, so `auto` tracks the system live.
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in if AppIcon.current == .auto { AppIcon.apply() } }
        }
        discovery.start() // always browse, so the Hosts list stays live in either role

        // Start/stop the local Host to match the chosen role. @Published replays the current value to
        // a new subscriber, so this also performs the initial start (host) or no-op (viewer) on launch.
        roleStore.$mode
            .sink { [weak self] mode in
                guard let self else { return }
                switch mode {
                case .host:   self.engine.start()
                case .viewer: self.engine.stop()
                }
            }
            .store(in: &cancellables)
    }

    func applicationWillTerminate(_ notification: Notification) {
        display.stop()
        discovery.stop()
        engine.stop()
    }
}

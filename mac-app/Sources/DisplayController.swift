import Foundation
import AppKit

// Drives the Display role by launching REAL Google Chrome in kiosk mode at a Host's /display
// (MAC-APP-PLAN §B4, and the 2026-07-01 decision). Chrome — not an in-app WKWebView — because
// WKWebView is Apple WebKit, the same engine that tile-corrupts Golden Lining and other pieces
// (HANDOFF §20, 2026-06-30); real Chrome keeps rendering identical to the XXL frame's Chromium
// kiosk. The flags mirror the frame's `installer/kiosk/chromium-kiosk.sh` (minus the Linux/Wayland
// ones), and a dedicated user-data-dir keeps this fully separate from the user's normal Chrome.
@MainActor
final class DisplayController: ObservableObject {
    enum State: Equatable {
        case stopped
        case running
        case failed(String)
    }

    @Published private(set) var state: State = .stopped

    /// Screens that asked for a kiosk and did not get one. Auto Display covers these in black, so a
    /// screen never sits showing the owner's desktop while they are away (E12). Empty on the manual
    /// path, which only ever targets one screen and blacks out nothing.
    @Published private(set) var uncoveredScreens: [NSScreen] = []

    private var kiosks: [NSRunningApplication] = []  // the Chrome instances we launched, one per screen
    private var exitObserver: NSObjectProtocol?   // fires if any of them quits on its own
    private var activity: NSObjectProtocol?       // power assertion held while the display is showing

    // Standard install location of Google Chrome on macOS.
    private let chromeAppURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")

    var isChromeInstalled: Bool {
        FileManager.default.fileExists(atPath: chromeAppURL.path)
    }

    // Open the given URL full-screen in a Chrome kiosk window.
    //
    // `onEveryScreen` is Auto Display's mode (E12): one kiosk per attached screen, because the macOS
    // screen saver covers every display and Auto Display exists to emulate it. Each screen runs its
    // OWN rotation, which is also what a screen saver does (a photo saver shows a different photo per
    // screen); syncing them to the same piece was weighed and closed, see ROADMAP D17.
    //
    // The manual path leaves it off and keeps its long-standing behavior: ONE kiosk, placed wherever
    // Chrome would naturally open it. An owner who deliberately asks for a display still has their
    // other screens to work on, which is the opposite of what a screen saver should do.
    func show(url: URL, onEveryScreen: Bool = false) {
        guard isChromeInstalled else {
            state = .failed("Google Chrome is required to show the display.")
            return
        }
        stop() // replace any running display
        watchForExit()

        guard onEveryScreen else {
            launch(url: url, profile: "chrome-display", position: nil, screen: nil)
            return
        }
        // Deliberately NOT NSScreen.screens.count profiles: a mirrored set can report the same screen
        // twice, and two kiosks stacked on one panel is double the render cost for nothing.
        for (i, screen) in Self.distinctScreens().enumerated() {
            launch(url: url, profile: "chrome-display-\(i)", position: Self.chromeOrigin(of: screen), screen: screen)
        }
    }

    /// One entry per physically distinct screen. Mirrored displays are reported by macOS as separate
    /// `NSScreen`s sharing a frame, so de-duplicating by frame collapses a mirror set to one kiosk.
    /// Correct whichever way macOS reports mirroring, which is why it is done rather than tested for.
    private static func distinctScreens() -> [NSScreen] {
        var seen: [CGRect] = []
        return NSScreen.screens.filter { screen in
            guard !seen.contains(screen.frame) else { return false }
            seen.append(screen.frame)
            return true
        }
    }

    /// A screen's origin in Chrome's coordinate space.
    ///
    /// AppKit measures up from the bottom-left of the primary screen; Chrome's `--window-position`
    /// measures down from the top-left. The two agree ONLY at the primary screen's origin, which is
    /// why the old `pinToPrimaryScreen` could hardcode `0,0` and never meet this. Measured on a real
    /// two-screen setup: a display AppKit reports at y = -513 is y = 1197 to Chrome. Hand Chrome the
    /// AppKit value and the window lands off-canvas, and Chrome quietly falls back to the primary.
    private static func chromeOrigin(of screen: NSScreen) -> CGPoint {
        guard let primary = NSScreen.screens.first else { return .zero }
        return CGPoint(x: screen.frame.origin.x, y: primary.frame.maxY - screen.frame.maxY)
    }

    // Launch one kiosk. `screen` is only carried so a failed launch can be reported as an uncovered
    // screen; placement itself is entirely decided by `position`.
    private func launch(url: URL, profile name: String, position: CGPoint?, screen: NSScreen?) {
        // A profile PER SCREEN, not one shared: Chrome is a singleton per --user-data-dir, so a second
        // launch against the same profile silently joins the first instance and ignores every switch
        // below, including --kiosk. That fails as an ordinary browser window rather than as an error.
        let profile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenObject/\(name)", isDirectory: true)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        var args = [
            "--kiosk",                                   // full-screen, zero chrome (HANDOFF §6)
            "--user-data-dir=\(profile.path)",           // dedicated profile; never touches the user's Chrome
            "--no-first-run",
            "--no-default-browser-check",
            "--noerrdialogs",
            "--disable-infobars",
            "--disable-session-crashed-bubble",
            "--disable-features=Translate,TranslateUI",
            "--disable-pinch",
            "--overscroll-history-navigation=0",
            "--hide-scrollbars",
            "--autoplay-policy=no-user-gesture-required", // video pieces play without a gesture (muted)
            "--disable-component-update",
            "--check-for-update-interval=31536000",
            "--password-store=basic",
        ]
        // Chrome picks its screen from the window position, then goes full-screen on that one.
        if let position { args.append("--window-position=\(Int(position.x)),\(Int(position.y))") }
        args.append(url.absoluteString)

        // LAUNCH THROUGH LAUNCHSERVICES, NOT BY EXEC'ING CHROME'S BINARY (2026-08-06).
        //
        // Running `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome` as a child process made
        // OpenObject Chrome's parent and therefore its RESPONSIBLE PROCESS for permissions. So when Chrome
        // touched its own app bundle at startup (finalizing one of its auto-updates), macOS App Management
        // blocked it and told the owner "OpenObject was prevented from modifying apps on your Mac", a
        // security warning naming us for something Chrome did. Measured 2026-08-06: the notification fired
        // 0.3s after Chrome started. Opening the .app through NSWorkspace makes Chrome its own responsible
        // process, so its own housekeeping is attributed to Chrome and never surfaces as our warning.
        //
        // `createsNewApplicationInstance` matters: without it this could adopt the owner's ALREADY-RUNNING
        // Chrome and ignore every switch below, including --kiosk and the separate profile.
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = args
        config.createsNewApplicationInstance = true
        config.activates = true

        NSWorkspace.shared.openApplication(at: chromeAppURL, configuration: config) { [weak self] app, error in
            Task { @MainActor in
                guard let self else { return }
                guard let app else {
                    // One screen failing must not take down the screens that did come up, so this only
                    // reports the gap. It becomes a black cover rather than the owner's exposed desktop.
                    if let screen { self.uncoveredScreens.append(screen) }
                    if self.kiosks.isEmpty {
                        self.state = .failed("Could not launch Chrome: \(error?.localizedDescription ?? "unknown error")")
                    }
                    return
                }
                self.kiosks.append(app)
                self.beginKeepAwake()
                self.state = .running
            }
        }
    }

    // Notice a kiosk quitting on its own (the owner closed it from inside the display). With a child
    // Process this was `terminationHandler`; an app opened through LaunchServices reports it here instead.
    //
    // ANY kiosk going away ends the whole session, rather than leaving art on some screens and desktop
    // on others. That matches how the session ends by every other route: one input dismisses all of it.
    private func watchForExit() {
        clearExitObserver()
        exitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let gone = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                guard let self,
                      self.kiosks.contains(where: { $0.processIdentifier == gone.processIdentifier })
                else { return }
                self.stop()
            }
        }
    }

    // Backstop for the observer above, which Matt's Cmd-Q test on 2026-08-06 proved is not dependable:
    // the kiosk had quit and the app still reported `.running`. That is not cosmetic. Auto Display skips
    // its trigger while a display is already running, so a missed exit would silently disable the feature
    // until the app was relaunched. `isTerminated` is a direct read of the process rather than a delivered
    // message, so this closes the gap however the kiosk goes away. Called from Auto Display's existing
    // tick, which runs every couple of seconds in either role.
    func reconcileIfExited() {
        guard kiosks.contains(where: { $0.isTerminated }) else { return }
        stop()
    }

    private func clearExitObserver() {
        if let exitObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(exitObserver)
            self.exitObserver = nil
        }
    }

    func stop() {
        clearExitObserver()
        uncoveredScreens = []
        // Return BEFORE touching `state` when nothing is running. `@Published` fires on every assignment,
        // equal or not, and Auto Display's subscriber reads any non-`.running` value as "the kiosk went
        // away" — so an unconditional `state = .stopped` here would make show()'s own opening stop() call
        // tear down the session it is in the middle of starting.
        guard !kiosks.isEmpty else { return }
        let running = kiosks
        kiosks = []
        endKeepAwake()
        state = .stopped
        // terminate() asks politely; a kiosk has nothing to save, and forceTerminate is the backstop.
        for app in running where !app.isTerminated {
            if !app.terminate() { app.forceTerminate() }
        }
    }

    // Bring the full-screen kiosk back to the front. It lives on its own macOS Space, so a user who
    // navigated away (to reach this app or another) may not know how to get back — the window offers
    // this as "Return to Display" while the display is running.
    func focusDisplay() {
        // With one kiosk per screen only one can hold focus; the first is the primary screen's, which is
        // where an owner looking for the display will be looking. The rest are already full-screen on
        // their own displays and need no raising.
        guard let app = kiosks.first else { return }
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: [.activateAllWindows])
        }
    }

    // Keep the Mac awake while showing art: without this the display would blank on idle sleep and the
    // art would stop. An OS power assertion (ProcessInfo.beginActivity) is more reliable than the web
    // Screen Wake Lock, which was tried and dropped (HANDOFF §20, 2026-06-30).
    private func beginKeepAwake() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
            reason: "OpenObject is showing art")
    }

    private func endKeepAwake() {
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
}

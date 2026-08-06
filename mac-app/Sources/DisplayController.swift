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

    private var kiosk: NSRunningApplication?      // the Chrome instance we launched
    private var exitObserver: NSObjectProtocol?   // fires if that instance quits on its own
    private var activity: NSObjectProtocol?       // power assertion held while the display is showing

    // Standard install location of Google Chrome on macOS.
    private let chromeAppURL = URL(fileURLWithPath: "/Applications/Google Chrome.app")

    var isChromeInstalled: Bool {
        FileManager.default.fileExists(atPath: chromeAppURL.path)
    }

    // Open the given URL full-screen in a Chrome kiosk window. One display at a time.
    //
    // `pinToPrimaryScreen` steers the kiosk onto the screen carrying the menu bar. Auto Display passes
    // it because it blacks out the other screens, so the art has to land on the one screen it left
    // alone (HANDOFF §17). The manual path leaves it off, keeping its long-standing behavior of opening
    // wherever Chrome would naturally open.
    func show(url: URL, pinToPrimaryScreen: Bool = false) {
        guard isChromeInstalled else {
            state = .failed("Google Chrome is required to show the display.")
            return
        }
        stop() // replace any running display

        let profile = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenObject/chrome-display", isDirectory: true)
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
        // Chrome picks its screen from the window position, then goes full-screen on that one. The
        // primary screen's origin is (0,0) in Chrome's top-left coordinate space.
        if pinToPrimaryScreen { args.append("--window-position=0,0") }
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
                    self.state = .failed("Could not launch Chrome: \(error?.localizedDescription ?? "unknown error")")
                    return
                }
                self.kiosk = app
                self.watchForExit(of: app)
                self.beginKeepAwake()
                self.state = .running
            }
        }
    }

    // Notice the kiosk quitting on its own (the owner closed it from inside the display). With a child
    // Process this was `terminationHandler`; an app opened through LaunchServices reports it here instead.
    private func watchForExit(of app: NSRunningApplication) {
        clearExitObserver()
        exitObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let gone = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard gone?.processIdentifier == app.processIdentifier else { return }
            Task { @MainActor in
                guard let self, self.kiosk != nil else { return }
                self.kiosk = nil
                self.clearExitObserver()
                self.endKeepAwake()
                self.state = .stopped
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
        guard let app = kiosk, app.isTerminated else { return }
        kiosk = nil
        clearExitObserver()
        endKeepAwake()
        state = .stopped
    }

    private func clearExitObserver() {
        if let exitObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(exitObserver)
            self.exitObserver = nil
        }
    }

    func stop() {
        guard let app = kiosk else { return }
        kiosk = nil
        clearExitObserver()
        endKeepAwake()
        state = .stopped
        // terminate() asks politely; the kiosk has nothing to save, and forceTerminate is the backstop.
        if !app.terminate() { app.forceTerminate() }
    }

    // Bring the full-screen kiosk back to the front. It lives on its own macOS Space, so a user who
    // navigated away (to reach this app or another) may not know how to get back — the window offers
    // this as "Return to Display" while the display is running.
    func focusDisplay() {
        guard let app = kiosk else { return }
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

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

    private var process: Process?
    private var activity: NSObjectProtocol?  // power assertion held while the display is showing

    // Standard install location of Google Chrome on macOS.
    private let chromePath = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

    var isChromeInstalled: Bool {
        FileManager.default.fileExists(atPath: chromePath)
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

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: chromePath)
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
        proc.arguments = args
        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.process != nil else { return }
                // Chrome exited on its own (e.g. the user quit the kiosk window).
                self.process = nil
                self.endKeepAwake()
                self.state = .stopped
            }
        }

        do {
            try proc.run()
            process = proc
            beginKeepAwake()
            state = .running
        } catch {
            state = .failed("Could not launch Chrome: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let proc = process else { return }
        process = nil
        endKeepAwake()
        state = .stopped
        proc.terminationHandler = nil
        proc.terminate()
    }

    // Bring the full-screen kiosk back to the front. It lives on its own macOS Space, so a user who
    // navigated away (to reach this app or another) may not know how to get back — the window offers
    // this as "Return to Display" while the display is running.
    func focusDisplay() {
        guard let pid = process?.processIdentifier,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
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

import AppKit
import Combine

// Auto Display: the Mac shows art after a period of inactivity, and the first touch of the keyboard
// or trackpad puts the desktop back exactly as it was (HANDOFF §17, designed 2026-08-02, device-tested
// 2026-08-05).
//
// This is a TRIGGER, NOT A RENDERER. It draws no art of its own; it only decides when to call the
// DisplayController methods the manual "Open Display" path already uses. So it inherits the exact
// fidelity of the normal display: every Connected Collection, Folder Collections, video, and the Sound
// setting behave identically, with nothing reimplemented.
//
// DEFAULT IS `never`, AND THAT MEANS ZERO IMPACT. An owner must be able to run OpenObject without it
// changing their Mac's idle behavior at all. That holds by construction: the power assertion lives
// only in DisplayController.show()/stop(), so an app that is running but not displaying holds none,
// and at `never` this controller starts no timer and never calls show(). Do not regress this.

/// How long the Mac sits idle before art appears. Mirrors Apple's own screen saver control, which on
/// macOS 26 lives in System Settings > Wallpaper (NOT Lock Screen) as "Start Screen Saver": one pop-up
/// of fixed presets with Never as the last item rather than a separate checkbox. The intervals and the
/// "After N minutes" phrasing are Apple's exactly (verified from Matt's Mac 2026-08-05); note Apple
/// says "After" for the screen saver and "For" for the display-off settings.
enum AutoDisplayInterval: Int, CaseIterable, Identifiable {
    case never = 0
    case min1 = 60
    case min2 = 120
    case min3 = 180
    case min5 = 300
    case min10 = 600
    case min20 = 1200
    case min30 = 1800
    case hr1 = 3600
    case hr1min30 = 5400
    case hr2 = 7200
    case hr2min30 = 9000
    case hr3 = 10800

    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var minutes: Int { rawValue / 60 }

    var label: String {
        switch self {
        case .never: return "Never"
        case .min1: return "After 1 minute"
        case .min2: return "After 2 minutes"
        case .min3: return "After 3 minutes"
        case .min5: return "After 5 minutes"
        case .min10: return "After 10 minutes"
        case .min20: return "After 20 minutes"
        case .min30: return "After 30 minutes"
        case .hr1: return "After 1 hour"
        case .hr1min30: return "After 1 hour, 30 minutes"
        case .hr2: return "After 2 hours"
        case .hr2min30: return "After 2 hours, 30 minutes"
        case .hr3: return "After 3 hours"
        }
    }

    /// Apple lists Never last, not first.
    static var menuOrder: [AutoDisplayInterval] {
        allCases.filter { $0 != .never } + [.never]
    }

    static let key = "autoDisplaySeconds"
    static var current: AutoDisplayInterval {
        AutoDisplayInterval(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .never
    }
}

@MainActor
final class AutoDisplayController: ObservableObject {
    private let display: DisplayController
    private let actions: DisplayActions

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var blackout: [NSWindow] = []

    /// True only while THIS controller opened the display. A display the owner opened by hand is left
    /// alone: their mouse movement must not tear down a display they asked for.
    private(set) var isShowing = false
    /// The idle reading at the moment we triggered. Idle time only ever climbs or resets to ~0, and the
    /// trigger value is at least 60s, so any later sample below it is unmistakably a fresh input event.
    private var triggerIdle: TimeInterval = 0
    /// When we triggered, so a display that never comes up can be backed out of (see `stallTimeout`).
    private var triggeredAt = Date.distantPast

    /// If the kiosk has not reached `.running` this long after triggering, give up and undo. Without
    /// this, a Viewer-mode Mac whose remembered Host is not currently on the network would black out its
    /// secondary screens and then show no art at all, because `DisplayActions.resolveActiveBase` returns
    /// silently when the Host is missing from the live Bonjour list. Backing out leaves the desktop as
    /// it was rather than stranding black rectangles across it.
    private let stallTimeout: TimeInterval = 12

    // Two cadences: a lazy one while waiting (nothing is on screen, so precision is worthless) and a
    // brisk one while art is up, where the delay between touching the trackpad and getting the desktop
    // back is the whole feel of the feature.
    private let waitingPoll: TimeInterval = 2
    private let showingPoll: TimeInterval = 0.25

    init(display: DisplayController, actions: DisplayActions) {
        self.display = display
        self.actions = actions

        // If the kiosk goes away on its own (the owner quit Chrome from inside the display), drop the
        // blackout screens with it rather than stranding black rectangles over their desktop.
        display.$state
            .sink { [weak self] state in
                guard let self, self.isShowing, state != .running else { return }
                Task { @MainActor in self.finish(stopDisplay: false) }
            }
            .store(in: &cancellables)
    }

    /// Begin watching. Safe to call once at launch: at `never` the tick does nothing at all.
    func start() { schedule(waitingPoll) }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isShowing { finish(stopDisplay: true) }
    }

    private func schedule(_ interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // .common so the countdown keeps running while a menu is open or a window is being dragged.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let setting = AutoDisplayInterval.current
        let idle = Self.systemIdleSeconds()

        if isShowing {
            if idle < triggerIdle { finish(stopDisplay: true) }   // the owner is back
            else if display.state != .running, Date().timeIntervalSince(triggeredAt) > stallTimeout {
                finish(stopDisplay: true)                          // it never came up; undo cleanly
            }
            return
        }

        // Everything below this line is skipped entirely at `never`.
        guard setting != .never else { return }
        // Never fight a display the owner opened by hand, and never stack a second one.
        guard display.state != .running else { return }
        guard idle >= setting.seconds else { return }

        begin(idleAtTrigger: idle)
    }

    private func begin(idleAtTrigger: TimeInterval) {
        isShowing = true
        triggerIdle = idleAtTrigger
        triggeredAt = Date()
        showBlackout()
        actions.openDisplay(pinToPrimaryScreen: true)
        schedule(showingPoll)
    }

    private func finish(stopDisplay: Bool) {
        isShowing = false
        triggerIdle = 0
        if stopDisplay { actions.stopDisplay() }
        hideBlackout()
        schedule(waitingPoll)
    }

    // MARK: - Secondary screens

    // Cover every attached screen, art on the main one, the rest black (HANDOFF §17). A real screen
    // saver fills every screen, so covering only the main display would leave the others glowing with
    // the owner's work while they are away. But art on every screen is wrong too: the rotation is
    // client-side, so N kiosks would drift out of step within minutes and each would cost a full video
    // decode. Black secondaries satisfy the convention for free.
    private func showBlackout() {
        hideBlackout()
        guard let primary = NSScreen.screens.first else { return }
        for screen in NSScreen.screens where screen != primary {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            // Swallow clicks rather than letting them through: any input dismisses within a quarter
            // second anyway, and a pass-through click would also land on whatever app is underneath.
            w.ignoresMouseEvents = false
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            blackout.append(w)
        }
    }

    private func hideBlackout() {
        blackout.forEach { $0.orderOut(nil) }
        blackout.removeAll()
    }

    // MARK: - Idle time

    /// Seconds since the last human input, anywhere on the system. Needs NO permissions: this reads the
    /// window server's own idle clock rather than monitoring events (a global event monitor would need
    /// Accessibility, and first-run friction has to stay at zero).
    ///
    /// The C constant for "any input" (`kCGAnyInputEventType`, ~0) has no Swift `CGEventType` case, so
    /// it cannot be constructed here; taking the minimum over the input types is the equivalent, since
    /// the most recent input is the one with the smallest elapsed time.
    static func systemIdleSeconds() -> TimeInterval {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .rightMouseDragged,
            .otherMouseDown, .otherMouseDragged, .scrollWheel, .keyDown, .flagsChanged,
        ]
        return types
            .map { CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: $0) }
            .min() ?? 0
    }

    // MARK: - The display-off race

    /// The macOS "Turn display off when inactive" interval, in minutes, or nil if it is off or unreadable.
    ///
    /// This is the feature's one real footgun (HANDOFF §17). That timer is a separate macOS setting we do
    /// not control: if Auto Display's interval is longer, macOS blanks the screen BEFORE the art starts and
    /// it plays to a dark panel. Once art is running our power assertion holds the screen lit, so this only
    /// decides the initial race. Because Apple's interval list runs to three hours while a typical display
    /// sleep is ten minutes, most of the menu loses that race, which is why the setting warns rather than
    /// leaving the owner to wonder why nothing happened.
    static func displaySleepMinutes() -> Int? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let out = String(data: data, encoding: .utf8) else { return nil }
        for line in out.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 2, parts[0] == "displaysleep", let m = Int(parts[1]) else { continue }
            return m > 0 ? m : nil    // 0 means never sleep, so there is no race to lose
        }
        return nil
    }
}

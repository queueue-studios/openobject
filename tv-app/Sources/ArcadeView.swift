import SwiftUI
import UIKit
import GameController

// The Retro Arcade easter egg's tvOS surfaces (HANDOFF §20): the stage that runs the native port
// (ArcadeGame.swift), the hostless full-screen it opens into from the picker's hidden remote code, and
// the watcher that recognizes that code. Mirrors the iPad's ArcadeView.swift in shape; the web view is
// replaced by the native Canvas, the touch exits by the Siri Remote's Back button.

/// The running demo: a Canvas redrawn every display frame by a TimelineView. Fills whatever space it is
/// given with the game's own letterboxing (the square field centers on the shorter side; a 16:9 TV gets
/// the starfield wings). No chrome of its own; the screens below own focus and exit.
struct ArcadeStage: View {
    @State private var game = ArcadeGame()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                game.frame(now: timeline.date.timeIntervalSinceReferenceDate, context: &context, size: size)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
}

/// The local, hostless arcade reached from the Host picker's hidden remote code. Exactly the art stage's
/// shell: focusable with the ring disabled so Back (onExitCommand) reaches it, the screensaver held off
/// while it runs. Never persisted; a relaunch always wakes to the picker or art.
struct ArcadeScreen: View {
    let onExit: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ArcadeStage()
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onExitCommand { onExit() }
            .onAppear {
                focused = true
                UIApplication.shared.isIdleTimerDisabled = true
            }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { UIApplication.shared.isIdleTimerDisabled = true }
            }
    }
}

/// Recognizes the classic sequence on the Siri Remote while the Host picker is up: eight clickpad-ring
/// presses, then Play/Pause twice. It OBSERVES the remote through the
/// GameController framework and never touches the focus engine, so the picker keeps navigating normally;
/// the focus ring visibly hopping between rows during entry is the one side effect, silent and harmless
/// (nothing activates, since Play/Pause stands in for select, which would press the focused row).
///
/// The matcher is the Control Panel's (control.js) with the iPad's two additions: a long pause starts
/// over (the window is generous, every input must still match), and a wrong input that matches the first
/// step restarts at 1. A direction is one clickpad CLICK, read from where the finger sits as it clicks
/// (see attach), so one press is exactly one input.
@MainActor
final class ArcadeCodeWatcher {
    private enum Input: Equatable { case up, down, left, right, tap }
    private static let code: [Input] = [.up, .up, .down, .down, .left, .right, .left, .right, .tap, .tap]

    private var pos = 0
    private var at = Date.distantPast
    private var onComplete: (() -> Void)?
    /// The most recent touch position at edge strength, with when it was seen: the fallback for a click
    /// whose own touch never registered (see attach).
    private var lastEdge: (x: Float, y: Float, seen: Date)?
    private var connectObserver: NSObjectProtocol?
    private var attached: [GCController] = []

    func begin(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        pos = 0
        for controller in GCController.controllers() { attach(controller) }
        connectObserver = NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] note in
            guard let controller = note.object as? GCController else { return }
            MainActor.assumeIsolated { self?.attach(controller) }
        }
    }

    func end() {
        onComplete = nil
        for controller in attached {
            controller.microGamepad?.dpad.valueChangedHandler = nil
            controller.microGamepad?.buttonA.pressedChangedHandler = nil
            controller.microGamepad?.buttonX.pressedChangedHandler = nil
        }
        attached = []
        if let observer = connectObserver {
            NotificationCenter.default.removeObserver(observer)
            connectObserver = nil
        }
    }

    private func attach(_ controller: GCController) {
        guard let pad = controller.microGamepad else { return }
        if !attached.contains(where: { $0 === controller }) { attached.append(controller) }
        // A direction is read AT THE CLICK, from where the finger is when the clickpad physically
        // clicks (buttonA), which is exactly how tvOS itself decides an edge press from a select. Three
        // real-remote findings shaped this (2026-11-09): relative dpad values hear nothing from a
        // stationary ring press; classifying an absolute touch when it first crosses a threshold reads
        // where the thumb LANDED (anywhere), not the edge it settled on to press; and a QUICK re-press
        // at the same spot can click without its touch ever being reported, the pad reading an exact
        // (0,0) throughout. So: absolute values; classify at the click; a late touch gets one deferred
        // read; and an exact (0,0), meaning no touch rather than a centered one, falls back to the last
        // edge the finger was seen on. A registered touch near the center stays a plain select.
        pad.reportsAbsoluteDpadValues = true
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            if max(abs(x), abs(y)) >= 0.4 {
                MainActor.assumeIsolated { self?.lastEdge = (x, y, Date()) }
            }
        }
        pad.buttonA.pressedChangedHandler = { [weak self, weak pad] _, _, pressed in
            MainActor.assumeIsolated {
                guard let self, let pad, pressed else { return }
                if self.classifyClick(pad) { return }
                // A quick press can outrun the touch samples, so the pad still reads (0,0) at the click
                // (the second real-remote test lost two of eight presses this way). Read again once the
                // samples have landed; still centered then means a real select, which is not code input.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, weak pad] in
                    MainActor.assumeIsolated {
                        guard let self, let pad else { return }
                        _ = self.classifyClick(pad)
                    }
                }
            }
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                guard pressed else { return }
                self?.input(.tap)
            }
        }
    }

    /// Turn one clickpad click into a direction from where the finger sits — or, when no touch is
    /// registered at all (an exact 0,0), from the last edge it was seen on. Returns false for a click
    /// that still reads as an actual centered touch (a select, or samples not yet landed; the caller
    /// retries once for the latter).
    private func classifyClick(_ pad: GCMicroGamepad) -> Bool {
        var x = pad.dpad.xAxis.value, y = pad.dpad.yAxis.value
        if x == 0, y == 0, let edge = lastEdge, Date().timeIntervalSince(edge.seen) < 2 {
            x = edge.x; y = edge.y
        }
        guard max(abs(x), abs(y)) >= 0.4 else { return false }
        input(abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down))
        return true
    }

    private func input(_ input: Input) {
        let now = Date()
        if now.timeIntervalSince(at) > 10 { pos = 0 }
        at = now
        pos = input == Self.code[pos] ? pos + 1 : (input == Self.code[0] ? 1 : 0)
        if pos == Self.code.count {
            pos = 0
            onComplete?()
        }
    }
}

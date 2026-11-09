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

/// Recognizes the classic sequence on the Siri Remote while the Host picker is up: eight directions
/// (clickpad-ring presses or touch swipes), then Play/Pause twice. It OBSERVES the remote through the
/// GameController framework and never touches the focus engine, so the picker keeps navigating normally;
/// the focus ring visibly hopping between rows during entry is the one side effect, silent and harmless
/// (nothing activates, since Play/Pause stands in for select, which would press the focused row).
///
/// The matcher is the Control Panel's (control.js) with the iPad's two additions: a long pause starts
/// over (the window is generous, every input must still match), and a wrong input that matches the first
/// step restarts at 1. Directions come from the clickpad as an excursion past half deflection, latched
/// until the finger returns near rest so one press or swipe is one input.
@MainActor
final class ArcadeCodeWatcher {
    private enum Input: Equatable { case up, down, left, right, tap }
    private static let code: [Input] = [.up, .up, .down, .down, .left, .right, .left, .right, .tap, .tap]

    private var pos = 0
    private var at = Date.distantPast
    private var latched = false
    private var onComplete: (() -> Void)?
    private var connectObserver: NSObjectProtocol?
    private var attached: [GCController] = []

    func begin(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        pos = 0
        latched = false
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
        // Relative dpad values (the default): a touch starts at rest and a swipe is an excursion from it;
        // a clickpad-ring press jumps straight to full deflection. Both read as one direction here.
        pad.dpad.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated {
                guard let self else { return }
                let magnitude = max(abs(x), abs(y))
                if self.latched {
                    if magnitude < 0.25 { self.latched = false }
                    return
                }
                guard magnitude >= 0.5 else { return }
                self.latched = true
                self.input(abs(x) > abs(y) ? (x > 0 ? .right : .left) : (y > 0 ? .up : .down))
            }
        }
        pad.buttonX.pressedChangedHandler = { [weak self] _, _, pressed in
            MainActor.assumeIsolated {
                guard pressed else { return }
                self?.input(.tap)
            }
        }
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

import Foundation
import Observation

// The async driver that turns the pure RotationEngine into a live, observable rotation (§8) — the
// "thin glue" B4-B6 deliberately left for the app layer, placed HERE in DisplayCore so the tvOS and
// iPad apps share ONE driver and stay identical. It polls a Host's /api/display on an interval (the
// engine folds each response in without restarting the loop), advances on the global equal-time
// duration, and publishes `screen` for a SwiftUI view to render. It renders nothing itself: the art
// stage (the app) observes `screen` and draws it.
//
// @MainActor + @Observable: it owns UI-facing state and is driven from the main actor; SwiftUI observes
// `screen` directly. Timing lives here (Task.sleep), which is exactly why the ENGINE stayed timer-free
// and deterministically testable; this driver is exercised with an injected `fetch` and short intervals.

@MainActor
@Observable
public final class RotationPlayer {
    /// What the UI should present right now. A SwiftUI view observes this.
    public private(set) var screen: RotationEngine.Screen = .idle
    /// False until the first poll of the current Host succeeds; the UI shows a "Connecting…" state until
    /// then (§13). Stays true afterward even if later polls fail, so a Host that drops mid-playback holds
    /// its last frame rather than falling back to "Connecting" (§16: hold the last frame).
    public private(set) var hasConnected = false
    /// Whether the most recent poll of the current Host succeeded: false until the first success and again
    /// after any failure. The iPad overlay reads it to say "Playing local copy" (HANDOFF §17); `hasConnected`
    /// stays the stage's Connecting gate, since a seeded copy is something to show before any poll.
    public private(set) var hostReachable = false
    /// iPad local copy (§17): when true, a Host that stops answering while asleep is woken to its last
    /// rotation, because the device cannot know the Host's hours once the Host is gone (offline ignores the
    /// schedule). Off by default: tvOS holds whatever the Host last said, exactly as the web display does.
    public var wakesWhenHostUnreachable = false
    /// iOS Connected art (HANDOFF §17, phase one): when true, a Host that stops answering has its Connected
    /// pieces dropped from the running rotation, because a web view can only load them from a Host that
    /// answers; the next successful poll brings them back. Off by default: tvOS never renders them anyway.
    public var dropsConnectedWhenHostUnreachable = false
    /// With `dropsConnectedWhenHostUnreachable`: the Connected pieces to KEEP while the Host is gone, the ones
    /// the local copy holds a bundle for (§17 phase two). Nil keeps none.
    public var connectedHeldOffline: (@MainActor (DisplayItem) -> Bool)?
    /// iOS Connected art: when true, a Connected piece's duration is not counted until the stage reports it
    /// revealed (`pieceRevealed`); until then only a give-up timer runs, `revealGiveUp` from the pick, after
    /// which the rotation moves on without it. A bundle whose generate outlasts a short Every (Azulejo Galo
    /// on a real iPad at 10 s) would otherwise lose its turn on every pass, where the frame waits for it.
    /// Off by default: tvOS never shows a Connected piece.
    public var holdsConnectedUntilRevealed = false
    /// How long a Connected piece may take to reveal before the rotation moves on (display.js's backstop).
    public var revealGiveUp: Duration = .seconds(30)
    /// The offline rotation override (§17, E26): while the Host is not answering, its duration and/or mode
    /// replace the captured ones. Ignored while the Host is reachable, and cleared by a successful poll, so
    /// an offline change lasts exactly until the device sees the Host again. Set it before `start` so a
    /// seeded start honors it, or any time after; a change while offline is applied at once and re-times
    /// the piece on screen.
    public private(set) var offlineOverride: RotationOverride?

    private let fetch: @Sendable (Host) async throws -> DisplayResponse
    private let engine: RotationEngine
    private let pollInterval: Duration

    private var pollTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var shownID: String?   // the id whose duration the advance timer is currently counting
    private var lastResponse: DisplayResponse?   // what the engine last applied (a seed, or a live poll)

    /// Designated init: `fetch` is the /api/display source (injected in tests; the real one is a
    /// DisplayClient, via the convenience init below).
    public init(fetch: @escaping @Sendable (Host) async throws -> DisplayResponse,
                engine: RotationEngine = RotationEngine(),
                pollInterval: Duration = .seconds(5)) {
        self.fetch = fetch
        self.engine = engine
        self.pollInterval = pollInterval
    }

    /// App init: drive a Host through a DisplayClient.
    public convenience init(client: DisplayClient = DisplayClient(),
                            engine: RotationEngine = RotationEngine(),
                            pollInterval: Duration = .seconds(5)) {
        self.init(fetch: { try await client.fetchDisplay(from: $0) }, engine: engine, pollInterval: pollInterval)
    }

    /// Begin rendering `host`: poll it now and every `pollInterval`, advancing on each piece's duration.
    /// Replaces any current session.
    ///
    /// - Parameter seed: a rotation to play at once, before the Host has answered (the iPad's local copy,
    ///   §17). Art first, then the network: the seed is applied awake, the stage skips Connecting, and a live
    ///   answer folds in on top through the engine exactly as any later poll does. Nil (tvOS, the Gallery,
    ///   a Host with no copy) is the original behavior.
    public func start(host: Host, seed: DisplayResponse? = nil) {
        stop()
        hasConnected = false
        hostReachable = false
        lastResponse = nil
        if let seed {
            let awake = seed.awake
            lastResponse = awake
            engine.apply(awake.overridden(by: offlineOverride))
            hasConnected = true
            reconcile()
        }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // A failed poll keeps the current screen (playback is local), like display.js's catch.
                if let response = try? await self.fetch(host) {
                    self.hasConnected = true
                    self.hostReachable = true
                    self.lastResponse = response
                    self.offlineOverride = nil                   // the Host is back: its values rule (E26)
                    self.engine.apply(response)
                    self.reconcile()
                } else {
                    let wasReachable = self.hostReachable
                    self.hostReachable = false
                    // The Host is not answering: reshape what it last said for offline play, if anything
                    // about it has to change (gone while asleep: the copy plays on rather than holding a
                    // dark screen it cannot end; Connected pieces: dropped, a web view cannot load them;
                    // an override waiting from E26: applied now). Each reshaping happens once, since the
                    // stored response is replaced by its offline form.
                    if let last = self.lastResponse {
                        let offline = self.offlineShape(of: last)
                        if offline != last || (wasReachable && self.offlineOverride != nil) {
                            self.lastResponse = offline
                            self.engine.apply(offline.overridden(by: self.offlineOverride))
                            self.reconcile()
                        }
                    }
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    /// Set (or clear) the offline override (E26). While the Host is not answering the change applies at
    /// once: the engine folds the new duration/mode in without restarting the piece, and the advance timer
    /// is re-armed so "Every" counts from the piece on screen. While the Host is reachable it is only stored
    /// (and a successful poll clears it), so it can never fight the Host.
    public func setOfflineOverride(_ override: RotationOverride?) {
        offlineOverride = (override?.isEmpty == true) ? nil : override
        guard !hostReachable, let last = lastResponse else { return }
        engine.apply(offlineShape(of: last).awake.overridden(by: offlineOverride))
        reconcile()
        armAdvance()
    }

    /// The stage reports that `id` is now actually visible. If it is the current piece, its duration is
    /// counted from now: a piece's duration is visible time (HANDOFF §7), and a Connected bundle can take
    /// seconds to generate before it paints. Only the iOS web layer calls this; native media reveals within
    /// milliseconds of the pick, so the tvOS cadence is unchanged.
    public func pieceRevealed(id: String) {
        guard id == shownID else { return }
        armAdvance()
    }

    // The piece just picked is a Connected one whose duration waits for its reveal.
    private var currentHoldsForReveal: Bool {
        guard holdsConnectedUntilRevealed, case let .playing(item) = screen else { return false }
        return item.kind == .connected
    }

    /// Move to the next piece at once. The iOS web layer calls this when a Connected piece's web content
    /// process has died twice (HANDOFF §17): the piece cannot paint, so it gives up its turn rather than
    /// holding a black stage. A lone piece stays (the next pick is itself); the piece gets its normal turn
    /// again next pass.
    public func advanceNow() {
        engine.advance()
        reconcile()
    }

    // A response as it should play while the Host is not answering, per the app's options: awake if the
    // device wakes a gone Host, and without Connected pieces if it drops them. tvOS sets neither, so this
    // is the identity there.
    private func offlineShape(of response: DisplayResponse) -> DisplayResponse {
        var next = response
        if wakesWhenHostUnreachable, next.asleep { next = next.awake }
        if dropsConnectedWhenHostUnreachable, next.hasConnected {
            next = next.droppingConnected(unless: { connectedHeldOffline?($0) ?? false })
        }
        return next
    }

    /// Stop polling and advancing, and drop the timers.
    public func stop() {
        pollTask?.cancel(); pollTask = nil
        advanceTask?.cancel(); advanceTask = nil
        shownID = nil
    }

    // Publish the engine's screen and (re)arm the advance timer ONLY when the on-screen piece changed,
    // so a routine poll never resets a piece's duration (mirrors display.js arming advance from reveal).
    private func reconcile() {
        screen = engine.screen
        let currentID: String? = if case let .playing(item) = screen { item.id } else { nil }
        if currentID != shownID {
            shownID = currentID
            if currentHoldsForReveal {
                armGiveUp()                                   // count nothing until it reveals; give up late
            } else {
                armAdvance()                                  // a new piece appeared: count its duration
            }
        } else if engine.autoAdvances, advanceTask == nil {
            armAdvance()                                      // 1 -> many: resume cadence, don't restart
        } else if !engine.autoAdvances {
            advanceTask?.cancel(); advanceTask = nil          // many -> 1 / sleep / idle: stop advancing
        }
    }

    private func armAdvance() {
        armAdvance(after: .milliseconds(engine.durationMs))
    }

    // A Connected piece that has not revealed yet: move on after `revealGiveUp`, not after its duration.
    private func armGiveUp() {
        armAdvance(after: revealGiveUp)
    }

    private func armAdvance(after interval: Duration) {
        advanceTask?.cancel()
        guard engine.autoAdvances else { advanceTask = nil; return }  // a lone/pinned piece holds forever
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            self.engine.advance()
            self.reconcile()
        }
    }
}

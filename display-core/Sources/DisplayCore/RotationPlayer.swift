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

    private let fetch: @Sendable (Host) async throws -> DisplayResponse
    private let engine: RotationEngine
    private let pollInterval: Duration

    private var pollTask: Task<Void, Never>?
    private var advanceTask: Task<Void, Never>?
    private var shownID: String?   // the id whose duration the advance timer is currently counting

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
    public func start(host: Host) {
        stop()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                // A failed poll keeps the current screen (playback is local), like display.js's catch.
                if let response = try? await self.fetch(host) {
                    self.engine.apply(response)
                    self.reconcile()
                }
                try? await Task.sleep(for: self.pollInterval)
            }
        }
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
            armAdvance()                                      // a new piece appeared: count its duration
        } else if engine.autoAdvances, advanceTask == nil {
            armAdvance()                                      // 1 -> many: resume cadence, don't restart
        } else if !engine.autoAdvances {
            advanceTask?.cancel(); advanceTask = nil          // many -> 1 / sleep / idle: stop advancing
        }
    }

    private func armAdvance() {
        advanceTask?.cancel()
        guard engine.autoAdvances else { advanceTask = nil; return }  // a lone/pinned piece holds forever
        let interval = Duration.milliseconds(engine.durationMs)
        advanceTask = Task { [weak self] in
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let self else { return }
            self.engine.advance()
            self.reconcile()
        }
    }
}

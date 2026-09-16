import Testing
import Foundation
@testable import DisplayCore

@Suite @MainActor struct RotationPlayerTests {

    // A still item and a library response, built directly (no network / URL mocking).
    private func still(_ id: String) -> DisplayItem {
        DisplayItem(id: id, kind: .still, format: .png, fit: .fit, filename: "\(id).png", src: nil)
    }
    private func response(_ ids: [String], durationMs: Int) -> DisplayResponse {
        DisplayResponse(items: ids.map(still), durationMs: durationMs, mode: .sequence,
                        pinnedId: nil, asleep: false, source: .library)
    }
    private func host() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("h:3000")) }

    // Poll a condition up to a timeout instead of a fixed sleep, for robustness.
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    private func playingID(_ player: RotationPlayer) -> String? {
        if case let .playing(item) = player.screen { return item.id }
        return nil
    }

    @Test func pollsHostAndPublishesScreen() async throws {
        let resp = response(["1"], durationMs: 100_000)
        let player = RotationPlayer(fetch: { _ in resp }, pollInterval: .milliseconds(20))
        player.start(host: try host())
        await waitUntil { playingID(player) == "1" }
        #expect(playingID(player) == "1")
        player.stop()
    }

    @Test func advancesThroughPiecesOnDuration() async throws {
        let resp = response(["1", "2"], durationMs: 40)
        // A long poll interval so only the advance timer drives motion.
        let player = RotationPlayer(fetch: { _ in resp }, pollInterval: .seconds(100))
        player.start(host: try host())
        var seen = Set<String>()
        await waitUntil(.seconds(3)) {
            if let id = playingID(player) { seen.insert(id) }
            return seen.isSuperset(of: ["1", "2"])
        }
        #expect(seen.isSuperset(of: ["1", "2"]))   // it advanced across both pieces
        player.stop()
    }

    @Test func lonePieceHoldsForever() async throws {
        let resp = response(["solo"], durationMs: 30)
        let player = RotationPlayer(fetch: { _ in resp }, pollInterval: .seconds(100))
        player.start(host: try host())
        await waitUntil { playingID(player) == "solo" }
        try? await Task.sleep(for: .milliseconds(150))   // well past durationMs
        #expect(playingID(player) == "solo")              // never advanced (autoAdvances == false)
        player.stop()
    }

    @Test func stopFreezesTheScreen() async throws {
        let resp = response(["1", "2"], durationMs: 40)
        let player = RotationPlayer(fetch: { _ in resp }, pollInterval: .seconds(100))
        player.start(host: try host())
        await waitUntil { playingID(player) != nil }
        player.stop()
        let frozen = player.screen
        try? await Task.sleep(for: .milliseconds(150))
        #expect(player.screen == frozen)                  // no advance after stop
    }

    @Test func liveEditFoldsInWithoutRestart() async throws {
        // First a 1-piece rotation (holds), then a poll grows it to 2 (cadence resumes) — the current
        // piece is not restarted.
        let one = response(["a"], durationMs: 40)
        let two = response(["a", "b"], durationMs: 40)
        let responses = Sendbox([one, two, two, two, two])
        let player = RotationPlayer(fetch: { _ in responses.next() }, pollInterval: .milliseconds(30))
        player.start(host: try host())
        var seen = Set<String>()
        await waitUntil(.seconds(3)) {
            if let id = playingID(player) { seen.insert(id) }
            return seen.isSuperset(of: ["a", "b"])
        }
        #expect(seen.isSuperset(of: ["a", "b"]))          // grew 1 -> 2 and resumed advancing
        player.stop()
    }
}

// A tiny thread-safe queue so an injected fetch can return a sequence of responses across polls.
final class Sendbox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [DisplayResponse]
    init(_ items: [DisplayResponse]) { self.items = items }
    func next() -> DisplayResponse {
        lock.lock(); defer { lock.unlock() }
        return items.count > 1 ? items.removeFirst() : items[0]   // last one repeats
    }
}

// The iPad's local copy (HANDOFF §17): a seed plays before any poll, and a Host gone while asleep wakes.
@Suite @MainActor struct RotationPlayerSeedTests {
    private func still(_ id: String) -> DisplayItem {
        DisplayItem(id: id, kind: .still, format: .png, fit: .fit, filename: "\(id).png", src: nil)
    }
    private func response(_ ids: [String], asleep: Bool = false) -> DisplayResponse {
        DisplayResponse(items: ids.map(still), durationMs: 100_000, mode: .sequence,
                        pinnedId: nil, asleep: asleep, source: .library)
    }
    private func host() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("h:3000")) }
    private func playingID(_ player: RotationPlayer) -> String? {
        if case let .playing(item) = player.screen { return item.id }
        return nil
    }
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func seededStartPlaysAtOnceWithoutTheHost() async throws {
        struct Unreachable: Error {}
        let player = RotationPlayer(fetch: { _ in throw Unreachable() }, pollInterval: .milliseconds(20))
        player.start(host: try host(), seed: response(["copy"], asleep: true))
        #expect(playingID(player) == "copy")                  // synchronously, before any poll
        #expect(player.hasConnected)                          // no Connecting screen
        #expect(!player.hostReachable)                        // but honest about the Host
        try? await Task.sleep(for: .milliseconds(80))
        #expect(playingID(player) == "copy")                  // failed polls change nothing
        player.stop()
    }

    @Test func liveAnswerFoldsInOverTheSeed() async throws {
        let live = response(["live"])
        let player = RotationPlayer(fetch: { _ in live }, pollInterval: .seconds(100))
        player.start(host: try host(), seed: response(["copy"]))
        await waitUntil { playingID(player) == "live" }
        #expect(playingID(player) == "live" && player.hostReachable)
        player.stop()
    }

    @Test func hostGoneWhileAsleepWakesOnlyWhenAsked() async throws {
        struct Unreachable: Error {}
        let script = Sendbox([response(["a"], asleep: true)])
        let gone = Flag()
        let fetch: @Sendable (DisplayCore.Host) async throws -> DisplayResponse = { _ in
            if await gone.value { throw Unreachable() }
            return script.next()
        }
        let holds = RotationPlayer(fetch: fetch, pollInterval: .milliseconds(20))
        holds.start(host: try host())
        await waitUntil { holds.screen == .sleeping }
        await gone.set(true)
        try? await Task.sleep(for: .milliseconds(80))
        #expect(holds.screen == .sleeping)                    // default: hold what the Host last said
        holds.stop()

        await gone.set(false)
        let wakes = RotationPlayer(fetch: fetch, pollInterval: .milliseconds(20))
        wakes.wakesWhenHostUnreachable = true
        wakes.start(host: try host())
        await waitUntil { wakes.screen == .sleeping }
        await gone.set(true)
        await waitUntil { playingID(wakes) == "a" }
        #expect(playingID(wakes) == "a" && !wakes.hostReachable)
        wakes.stop()
    }
}

actor Flag {
    private(set) var value = false
    func set(_ v: Bool) { value = v }
}

// Offline rotation controls (HANDOFF §17, E26): the override applies only while the Host is not answering.
@Suite @MainActor struct RotationPlayerOverrideTests {
    private func still(_ id: String) -> DisplayItem {
        DisplayItem(id: id, kind: .still, format: .png, fit: .fit, filename: "\(id).png", src: nil)
    }
    private func response(_ ids: [String], durationMs: Int = 100_000, mode: RotationMode = .sequence) -> DisplayResponse {
        DisplayResponse(items: ids.map(still), durationMs: durationMs, mode: mode,
                        pinnedId: nil, asleep: false, source: .library)
    }
    private func host() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("h:3000")) }
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func overrideShapesASeededOfflineStartAndClearsWhenTheHostAnswers() async throws {
        struct Unreachable: Error {}
        let gone = Flag()
        await gone.set(true)
        let live = response(["a", "b"], durationMs: 100_000, mode: .sequence)
        let engine = RotationEngine()
        let player = RotationPlayer(fetch: { _ in
            if await gone.value { throw Unreachable() }
            return live
        }, engine: engine, pollInterval: .milliseconds(20))
        player.setOfflineOverride(RotationOverride(durationMs: 7_000, mode: .shuffle))
        player.start(host: try host(), seed: response(["a", "b"]))
        #expect(engine.durationMs == 7_000)                    // the seed played with the override
        #expect(player.offlineOverride?.mode == .shuffle)

        player.setOfflineOverride(RotationOverride(durationMs: 9_000, mode: .shuffle))
        #expect(engine.durationMs == 9_000)                    // an offline change applies at once

        await gone.set(false)
        await waitUntil { player.hostReachable }
        #expect(engine.durationMs == 100_000)                  // the Host is back: its values rule
        #expect(player.offlineOverride == nil)                 // and the override is gone
        player.stop()
    }

    @Test func overrideWaitsWhileReachableAndAppliesWhenTheHostDrops() async throws {
        struct Unreachable: Error {}
        let gone = Flag()
        let live = response(["a"], durationMs: 50_000)
        let engine = RotationEngine()
        let player = RotationPlayer(fetch: { _ in
            if await gone.value { throw Unreachable() }
            return live
        }, engine: engine, pollInterval: .milliseconds(20))
        player.start(host: try host())
        await waitUntil { player.hostReachable }
        player.setOfflineOverride(RotationOverride(durationMs: 4_000))
        #expect(engine.durationMs == 50_000)                   // stored, not applied, while live
        // A successful poll clears it (the Host rules).
        try? await Task.sleep(for: .milliseconds(60))
        #expect(player.offlineOverride == nil)
        // Set again, then the Host drops: applied on the first failed poll.
        player.setOfflineOverride(RotationOverride(durationMs: 4_000))
        await gone.set(true)
        await waitUntil { !player.hostReachable && engine.durationMs == 4_000 }
        #expect(engine.durationMs == 4_000)
        player.stop()
    }
}

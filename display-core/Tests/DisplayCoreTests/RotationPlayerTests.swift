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

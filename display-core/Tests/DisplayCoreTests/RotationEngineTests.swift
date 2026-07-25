import Testing
import Foundation
@testable import DisplayCore

@Suite struct RotationEngineTests {

    // MARK: Sequence + lone piece

    @Test func startsOnFirstApplyThenSequencesAndWraps() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a"), item("b"), item("c")]))
        #expect(playingID(e) == "a")     // apply starts playback
        e.advance(); #expect(playingID(e) == "b")
        e.advance(); #expect(playingID(e) == "c")
        e.advance(); #expect(playingID(e) == "a")   // wraps
    }

    @Test func lonePieceHoldsAndDoesNotAutoAdvance() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("solo")]))
        #expect(playingID(e) == "solo")
        #expect(e.autoAdvances == false)
        e.advance()                                  // no-op even if called
        #expect(playingID(e) == "solo")
    }

    @Test func durationComesFromResponse() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a"), item("b")], durationMs: 30_000))
        #expect(e.durationMs == 30_000)
    }

    // MARK: Capability filter (§2, §6)

    @Test func skipsConnectedSvgAndWebm() {
        let e = RotationEngine()
        e.apply(libraryResponse([
            item("con", .connected),
            item("vid", .video, .mp4),
            item("svg", .animated, .svg),
            item("still", .still, .png),
            item("web", .video, .webm),
        ]))
        var seen = Set<String>()
        for _ in 0..<6 { if let id = playingID(e) { seen.insert(id) }; e.advance() }
        #expect(seen == ["vid", "still"])            // connected/svg/webm never shown
    }

    @Test func realMixedLibraryRotatesOnlyRenderable() throws {
        let e = RotationEngine()
        e.apply(try loadDisplayFixture("display-library")) // connected(4)/video(5)/still(6)/animated(7)
        var seen = Set<String>()
        for _ in 0..<6 { if let id = playingID(e) { seen.insert(id) }; e.advance() }
        #expect(seen == ["5", "6", "7"])             // the connected piece (4) is skipped
    }

    // MARK: Pin (§7, §8)

    @Test func pinnedRenderablePieceHoldsAlone() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a"), item("b"), item("c")], pinnedId: "b"))
        #expect(playingID(e) == "b")
        #expect(e.autoAdvances == false)             // collapsed to one -> holds
    }

    @Test func pinnedConnectedShowsSplashNeverSubstitutes() throws {
        // §8: a pinned Connected piece is the whole rotation and cannot render -> splash.
        let e = RotationEngine()
        e.apply(try loadDisplayFixture("display-pinned-connected")) // pinnedId 4, items = [connected]
        #expect(e.screen == .idle)
    }

    // MARK: Fold-in without restart (§8)

    @Test func currentPieceSurvivesReorder() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a"), item("b"), item("c")]))
        e.advance()
        #expect(playingID(e) == "b")
        e.apply(libraryResponse([item("c"), item("b"), item("a")])) // reordered, b still present
        #expect(playingID(e) == "b")                 // stays on b (no restart)
        e.advance()                                   // sequence continues from b's NEW index (1) -> a
        #expect(playingID(e) == "a")
    }

    @Test func deletedCurrentIsSkipped() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a"), item("b"), item("c")]))
        e.advance()
        #expect(playingID(e) == "b")
        e.apply(libraryResponse([item("a"), item("c")])) // b deleted
        #expect(playingID(e) != "b")
        #expect(["a", "c"].contains(playingID(e)!))
    }

    @Test func liveFitFlipReRendersInPlace() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a", fit: .fit), item("b")]))
        #expect(e.screen == .playing(item("a", fit: .fit)))
        e.apply(libraryResponse([item("a", fit: .fill), item("b")]))
        #expect(e.screen == .playing(item("a", fit: .fill)))  // same id, new fit -> re-rendered
    }

    @Test func oneToManyBecomesAutoAdvancing() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a")]))
        #expect(e.autoAdvances == false)
        e.apply(libraryResponse([item("a"), item("b")]))
        #expect(e.autoAdvances == true)              // driver resumes cadence
        #expect(playingID(e) == "a")                 // still on a, not restarted
    }

    // MARK: Sleep (§13) + empty

    @Test func sleepShowsSleepScreenThenResumes() {
        let e = RotationEngine()
        e.apply(libraryResponse([item("a"), item("b")]))
        #expect(playingID(e) == "a")
        e.apply(libraryResponse([item("a"), item("b")], asleep: true))
        #expect(e.screen == .sleeping)
        #expect(e.autoAdvances == false)
        e.apply(libraryResponse([item("a"), item("b")], asleep: false))
        #expect(playingID(e) != nil)                 // resumed to a real piece
    }

    @Test func emptyOrAllUnsupportedShowsIdle() {
        let e = RotationEngine()
        e.apply(libraryResponse([]))
        #expect(e.screen == .idle)
        e.apply(libraryResponse([item("c", .connected), item("s", .animated, .svg)]))
        #expect(e.screen == .idle)
    }

    // MARK: Shuffle (§7) — each piece once before repeating, no jarring immediate repeat

    @Test func shuffleVisitsEachOncePerPass() {
        let ids = ["a", "b", "c", "d", "e"]
        let e = RotationEngine(rng: SeededRNG(seed: 42))
        e.apply(libraryResponse(ids.map { item($0) }, mode: .shuffle))
        var seq: [String] = []
        for _ in 0..<(ids.count * 2) { seq.append(playingID(e)!); e.advance() }
        #expect(Set(seq.prefix(ids.count)) == Set(ids))               // pass 1: each once
        #expect(Set(seq.dropFirst(ids.count)) == Set(ids))            // pass 2: each once
    }

    @Test func shuffleNeverRepeatsConsecutively() {
        for seed: UInt64 in [1, 2, 3, 7, 42, 100, 2024] {
            let ids = ["a", "b", "c"]
            let e = RotationEngine(rng: SeededRNG(seed: seed))
            e.apply(libraryResponse(ids.map { item($0) }, mode: .shuffle))
            var seq: [String] = []
            for _ in 0..<(ids.count * 3) { seq.append(playingID(e)!); e.advance() }
            for i in 1..<seq.count {
                #expect(seq[i] != seq[i - 1], "seed \(seed) repeated at \(i): \(seq)")
            }
        }
    }

    @Test func unchangedPollDoesNotRestartShufflePass() {
        let ids = ["a", "b", "c", "d"]
        let resp = libraryResponse(ids.map { item($0) }, mode: .shuffle)
        let e = RotationEngine(rng: SeededRNG(seed: 5))
        e.apply(resp)
        var seen: [String] = [playingID(e)!]
        e.advance(); seen.append(playingID(e)!)
        e.apply(resp)                                 // an unchanged poll mid-pass
        e.advance(); seen.append(playingID(e)!)
        e.advance(); seen.append(playingID(e)!)
        #expect(Set(seen) == Set(ids))               // all four unique -> the pass was not restarted
    }
}

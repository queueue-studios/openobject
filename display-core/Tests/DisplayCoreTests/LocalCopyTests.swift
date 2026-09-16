import Testing
import Foundation
@testable import DisplayCore

// The local copy (HANDOFF §17): the store's reconcile / grace / reserve rules and the coordinator's fill
// passes, driven with injected downloads and a fake volume so nothing touches a network or a real disk budget.

@Suite struct LocalCopyStoreTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oo-localcopy-\(UUID().uuidString)")
    }
    private func hostA() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("a.local")) }
    private func hostB() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("b.local")) }

    /// Dependencies with a fake volume and a counted downloader that writes `size` bytes per file.
    private func deps(space: VolumeSpace? = nil, size: Int64 = 100, knowsSize: Bool = true,
                      counter: CallCounter, now: @escaping @Sendable () -> Date = { Date() })
        -> LocalCopyStore.Dependencies {
        LocalCopyStore.Dependencies(
            fetchSize: { _ in knowsSize ? size : nil },
            download: { _, dest in
                await counter.increment()
                try Data(repeating: 0xAB, count: Int(size)).write(to: dest)
            },
            space: { _ in space },
            now: now)
    }

    private func fillAll(_ store: LocalCopyStore) async -> [LocalCopySaveResult] {
        var attempted = Set<String>(), results: [LocalCopySaveResult] = []
        while let item = await store.nextMissing(excluding: attempted) {
            attempted.insert(LocalCopyStore.fileName(for: item))
            results.append(await store.save(item))
        }
        return results
    }

    @Test func adoptThenFillHoldsOnlyRenderablePieces() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let store = LocalCopyStore(directory: dir, dependencies: deps(counter: counter))
        let connected = DisplayItem(id: "c", kind: .connected, format: nil, fit: .fit, filename: "c.html", src: nil)
        let response = libraryResponse([item("a"), connected, item("b")])
        let outcome = await store.adopt(host: try hostA(), response: response)
        #expect(outcome.missing == 2)                                  // the Connected piece is not wanted
        let results = await fillAll(store)
        #expect(results == [.saved, .saved])
        #expect(await counter.count == 2)
        #expect(LocalCopyStore.heldFile(for: item("a"), in: dir) != nil)
        #expect(LocalCopyStore.heldFile(for: connected, in: dir) == nil)
        let counts = LocalCopyStore.counts(for: await store.current, in: dir)
        #expect(counts.total == 2 && counts.saved == 2)
        // The directory is marked out of iCloud backup.
        let values = try dir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func manifestRoundTripsAndSeedsAwakeWithHeldPiecesOnly() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalCopyStore(directory: dir, dependencies: deps(counter: CallCounter()))
        let response = libraryResponse([item("a"), item("b")], mode: .shuffle, asleep: true, durationMs: 12_000)
        _ = await store.adopt(host: try hostA(), response: response)
        // Hold only "a" (no fill for "b").
        let a = try #require(await store.nextMissing(excluding: []))
        #expect(await store.save(a) == .saved)

        let reread = try #require(LocalCopyStore.readManifest(in: dir))
        let current = try #require(await store.current)
        #expect(reread.host == current.host && reread.departed == current.departed)
        #expect(abs(reread.savedAt.timeIntervalSince(current.savedAt)) < 1)   // ISO 8601 keeps whole seconds
        #expect(reread.response == response)                           // what was written reads back whole

        let seed = try #require(LocalCopyStore.seed(from: reread, in: dir))
        #expect(seed.items.map(\.id) == ["a"])                          // only the held piece
        #expect(seed.asleep == false)                                   // offline ignores Sleep
        #expect(seed.mode == .shuffle && seed.durationMs == 12_000)     // the rest of the rotation survives
    }

    @Test func seedDropsAPinWhosePieceIsNotHeld() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalCopyStore(directory: dir, dependencies: deps(counter: CallCounter()))
        // The Host collapses items to the pinned piece on the wire, but a stale manifest may still name a
        // pin the device never fetched; here the pin names a piece that is simply not held.
        let response = libraryResponse([item("a"), item("b")], pinnedId: "b")
        _ = await store.adopt(host: try hostA(), response: response)
        let a = try #require(await store.nextMissing(excluding: []))    // "a" first, in rotation order
        _ = await store.save(a)
        let manifest = try #require(await store.current)
        let seed = try #require(LocalCopyStore.seed(from: manifest, in: dir))
        #expect(seed.pinnedId == nil && seed.items.map(\.id) == ["a"])
        #expect(LocalCopyStore.seed(from: LocalCopyManifest(host: try hostA(), response: libraryResponse([item("z")]),
                                                              savedAt: Date()), in: dir) == nil)   // nothing held
    }

    @Test func departedPieceIsKeptThroughTheGraceThenDeleted() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let clock = Clock(Date(timeIntervalSince1970: 1_000_000))
        let counter = CallCounter()
        let store = LocalCopyStore(directory: dir, grace: 3600, dependencies: deps(counter: counter, now: { clock.now }))
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a"), item("b")]))
        _ = await fillAll(store)
        #expect(await counter.count == 2)

        // "b" leaves the rotation (a Pin on "a" looks exactly like this on the wire).
        let pinned = await store.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        #expect(pinned.missing == 0)
        #expect(LocalCopyStore.heldFile(for: item("b"), in: dir) != nil)           // kept, within the grace
        #expect((await store.current)?.departed.count == 1)

        clock.advance(1800)
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        #expect(LocalCopyStore.heldFile(for: item("b"), in: dir) != nil)           // still within the grace

        // "b" comes back before the grace ends: no re-download, and it is no longer departed.
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a"), item("b")]))
        #expect(await fillAll(store).isEmpty)
        #expect(await counter.count == 2)
        #expect((await store.current)?.departed.isEmpty == true)

        // Leaves again and stays away past the grace: deleted.
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        clock.advance(3600)
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        #expect(LocalCopyStore.heldFile(for: item("b"), in: dir) == nil)
        #expect((await store.current)?.departed.isEmpty == true)
    }

    @Test func reserveBlocksAPieceAndDepartedPiecesYieldFirst() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        // A 100 GB volume keeps a 10 GB reserve; 10.5 GB free cannot take a 1 GB piece.
        let tight = VolumeSpace(available: 10_500_000_000, total: 100_000_000_000)
        let store = LocalCopyStore(directory: dir,
                                   dependencies: deps(space: tight, size: 1_000_000_000, counter: counter))
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        #expect(await fillAll(store) == [.skippedForSpace])
        #expect(await counter.count == 0)                              // never downloaded

        // With room, it saves; then it departs, and a new wanted piece purges it to try to make room.
        let roomy = VolumeSpace(available: 20_000_000_000, total: 100_000_000_000)
        let store2 = LocalCopyStore(directory: dir,
                                    dependencies: deps(space: roomy, size: 1_000_000_000, counter: counter))
        _ = await store2.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        #expect(await fillAll(store2) == [.saved])
        _ = await store2.adopt(host: try hostA(), response: libraryResponse([item("b")]))   // "a" departs
        #expect(LocalCopyStore.heldFile(for: item("a"), in: dir) != nil)
        let store3 = LocalCopyStore(directory: dir,
                                    dependencies: deps(space: tight, size: 1_000_000_000, counter: counter))
        _ = await store3.adopt(host: try hostA(), response: libraryResponse([item("b")]))
        #expect(await fillAll(store3) == [.skippedForSpace])
        #expect(LocalCopyStore.heldFile(for: item("a"), in: dir) == nil)  // the departed piece went first
    }

    @Test func unknownSizeIsVerifiedAfterDownload() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let tight = VolumeSpace(available: 9_000_000_000, total: 100_000_000_000)   // already under the reserve
        let store = LocalCopyStore(directory: dir,
                                   dependencies: deps(space: tight, knowsSize: false, counter: CallCounter()))
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        #expect(await fillAll(store) == [.skippedForSpace])
        #expect(LocalCopyStore.heldFile(for: item("a"), in: dir) == nil)
        #expect(LocalCopyStore.reserveBytes(forVolumeOf: 100_000_000_000) == 10_000_000_000)
        #expect(LocalCopyStore.reserveBytes(forVolumeOf: 32_000_000_000) == 5_000_000_000)   // the floor
    }

    @Test func aDifferentHostDropsThePreviousCopy() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalCopyStore(directory: dir, dependencies: deps(counter: CallCounter()))
        _ = await store.adopt(host: try hostA(), response: libraryResponse([item("a")]))
        _ = await fillAll(store)
        #expect(LocalCopyStore.heldFile(for: item("a"), in: dir) != nil)
        let outcome = await store.adopt(host: try hostB(), response: libraryResponse([item("a")]))
        #expect(outcome.missing == 1)                                  // same path, but B's copy starts empty
        #expect(LocalCopyStore.heldFile(for: item("a"), in: dir) == nil)
        #expect((await store.current)?.host.id == (try hostB()).id)
        await store.clear()
        #expect(await store.current == nil)
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func fileNameKeysOnTheHostRelativePath() throws {
        // The same piece on two addresses of one Host is one file; the extension survives for type sniffing.
        let byName = item("photo")
        let bySrc = DisplayItem(id: "x", kind: .video, format: .mp4, fit: .fill, filename: nil,
                                src: "/folder-media/k/clip%20one.mp4")
        #expect(LocalCopyStore.fileName(for: byName).hasSuffix(".jpg"))
        #expect(LocalCopyStore.fileName(for: bySrc).hasSuffix(".mp4"))
        #expect(LocalCopyStore.fileName(for: byName) != LocalCopyStore.fileName(for: item("other")))
        #expect(MediaPipeline.mediaPath(for: byName) == "/uploads/photo.jpg")
    }
}

@Suite @MainActor struct LocalCopyCoordinatorTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oo-localcopy-\(UUID().uuidString)")
    }
    private func host(_ s: String) throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry(s)) }

    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    private func deps(counter: CallCounter) -> LocalCopyStore.Dependencies {
        LocalCopyStore.Dependencies(
            fetchSize: { _ in 10 },
            download: { _, dest in
                await counter.increment()
                try Data(repeating: 1, count: 10).write(to: dest)
            },
            space: { _ in nil })
    }

    @Test func observeFillsAheadAndReportsStatusThenSeedsALaunch() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let copy = LocalCopy(directory: dir, dependencies: deps(counter: counter))
        #expect(copy.status == .empty && copy.host == nil)
        let h = try host("a.local")
        let response = libraryResponse([item("a"), item("b"), item("c")])
        await copy.observe(host: h, response: response)
        #expect(copy.host?.id == h.id)
        await waitUntil { copy.status.isComplete && !copy.status.isSaving }
        #expect(copy.status == LocalCopyStatus(total: 3, saved: 3, skippedForSpace: 0, isSaving: false))
        #expect(await counter.count == 3)
        #expect(copy.localFile(host: h, item: item("a")) != nil)
        #expect(copy.localFile(host: try host("b.local"), item: item("a")) == nil)   // Host-scoped

        // A fresh coordinator (a relaunch) sees the copy synchronously and can seed the stage.
        let relaunched = LocalCopy(directory: dir, dependencies: deps(counter: counter))
        #expect(relaunched.status.hasCopy && relaunched.host?.id == h.id)
        #expect(relaunched.seed(for: h)?.items.map(\.id) == ["a", "b", "c"])
        #expect(relaunched.seed(for: try host("b.local")) == nil)

        // The same poll again starts no new pass (nothing missing); an edit does.
        await copy.observe(host: h, response: response)
        #expect(!copy.status.isSaving)
        await copy.observe(host: h, response: libraryResponse([item("a"), item("d")]))
        await waitUntil { copy.status.isComplete && !copy.status.isSaving }
        #expect(copy.status.total == 2 && copy.status.saved == 2)
        #expect(await counter.count == 4)
    }

    @Test func clearEmptiesTheCopyAtOnce() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let copy = LocalCopy(directory: dir, dependencies: deps(counter: CallCounter()))
        let h = try host("a.local")
        await copy.observe(host: h, response: libraryResponse([item("a")]))
        await waitUntil { copy.status.isComplete }
        copy.clear()
        #expect(copy.status == .empty && copy.host == nil)
        #expect(copy.seed(for: h) == nil)
        await waitUntil { !FileManager.default.fileExists(atPath: dir.path) }
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }
}

/// A settable clock for grace-period tests.
final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); date = date.addingTimeInterval(seconds); lock.unlock() }
}

@Suite @MainActor struct LocalCopyOverrideTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oo-localcopy-\(UUID().uuidString)")
    }
    private func deps() -> LocalCopyStore.Dependencies {
        LocalCopyStore.Dependencies(fetchSize: { _ in 1 },
                                    download: { _, dest in try Data([1]).write(to: dest) },
                                    space: { _ in nil })
    }

    @Test func overridePersistsAcrossLaunchesAndClearsOnASuccessfulPoll() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "oo-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let copy = LocalCopy(directory: dir, dependencies: deps(), defaults: defaults)
        #expect(copy.override == nil)
        copy.setOverride(RotationOverride(durationMs: 60_000, mode: .shuffle))
        let relaunched = LocalCopy(directory: dir, dependencies: deps(), defaults: defaults)
        #expect(relaunched.override == RotationOverride(durationMs: 60_000, mode: .shuffle))   // survived
        // The Host answers: the override is gone, here and on disk.
        let h = try #require(DisplayCore.Host.manualEntry("a.local"))
        await relaunched.observe(host: h, response: libraryResponse([item("a")], mode: .sequence, durationMs: 8000))
        #expect(relaunched.override == nil)
        #expect(relaunched.capturedDurationMs == 8000 && relaunched.capturedMode == .sequence)
        #expect(LocalCopy(directory: dir, dependencies: deps(), defaults: defaults).override == nil)
        // An empty override is treated as none.
        relaunched.setOverride(RotationOverride())
        #expect(relaunched.override == nil)
    }
}

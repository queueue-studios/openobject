import Testing
import Foundation
@testable import DisplayCore

// The local copy carrying Connected pieces' bundles (HANDOFF §17 phase two, 2026-09-17): the Host's listing
// drives a per-file capture, a shared bundle serves every token, a re-mirrored file is refetched, a departed
// bundle ages out, and the seed and the player's offline filter see a held bundle as a playable piece.
@Suite struct ConnectedCopyTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oo-ccopy-\(UUID().uuidString)")
    }
    private func host() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("a.local")) }
    private let web = CapabilityFilter(rendersConnected: true)

    private func connected(_ id: String, slug: String, token: String, perToken: Bool) -> DisplayItem {
        DisplayItem(id: id, kind: .connected, format: nil, collection: slug, tokenId: token,
                    sourceURL: "https://x.test/?seed=\(token)", perToken: perToken)
    }

    /// Dependencies whose Host lists whatever `listings` says (keyed by the listing URL's path+query) and whose
    /// downloads write the requested URL's path as the file's content, so a file's identity is checkable.
    private func deps(listings: @escaping @Sendable (URL) -> BundleListing?, counter: CallCounter,
                      space: VolumeSpace? = nil, now: @escaping @Sendable () -> Date = { Date() }) -> LocalCopyStore.Dependencies {
        LocalCopyStore.Dependencies(
            fetchSize: { _ in 10 },
            download: { url, dest in
                await counter.increment()
                try Data(url.path.utf8).write(to: dest)
            },
            space: { _ in space },
            now: now,
            fetchListing: { url in
                guard let l = listings(url) else { throw LocalCopyError.httpStatus(404) }
                return l
            })
    }

    private func listing(_ base: String, _ files: [(String, Int64, Int64)]) -> BundleListing {
        BundleListing(base: base, files: files.map { .init(path: $0.0, bytes: $0.1, modified: $0.2) },
                      bytes: files.reduce(0) { $0 + $1.1 })
    }

    private func fillAll(_ store: LocalCopyStore) async -> [LocalCopySaveResult] {
        var attempted = Set<String>(), results: [LocalCopySaveResult] = []
        while let item = await store.nextMissing(excluding: attempted) {
            attempted.insert(LocalCopyStore.fileName(for: item))
            results.append(await store.save(item))
        }
        return results
    }

    @Test func listingDecodesTheHostsShape() throws {
        let json = Data(#"{"base":"/collections/inkfield","files":[{"path":"index.html","bytes":12,"modified":1700000000000},{"path":"lib/p5.js","bytes":3,"modified":5}],"bytes":15}"#.utf8)
        let l = try JSONDecoder().decode(BundleListing.self, from: json)
        #expect(l.base == "/collections/inkfield" && l.files.count == 2 && l.bytes == 15)
        #expect(l.files[1].path == "lib/p5.js")
    }

    @Test func bundleKeysSharedAndPerTokenPieces() {
        #expect(LocalCopyStore.bundleKey(for: connected("1", slug: "inkfield", token: "38", perToken: false)) == "bundle/inkfield")
        #expect(LocalCopyStore.bundleKey(for: connected("2", slug: "tiles", token: "86", perToken: true)) == "bundle/tiles/86")
        #expect(LocalCopyStore.fileName(for: connected("2", slug: "tiles", token: "86", perToken: true)) == "bundle/tiles/86")
    }

    @Test func capturesASharedBundleOnceForTwoTokensAndAPerTokenBundleForOne() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let store = LocalCopyStore(directory: dir, dependencies: deps(listings: { url in
            if url.path.hasSuffix("/inkfield/bundle") {
                return self.listing("/collections/inkfield", [("index.html", 5, 1), ("lib/p5.js", 7, 1)])
            }
            if url.path.hasSuffix("/tiles/bundle"), url.query == "token=86" {
                return self.listing("/collections/tiles/86", [("index.html", 9, 1)])
            }
            return nil
        }, counter: counter), filter: web)
        let ink31 = connected("31", slug: "inkfield", token: "31", perToken: false)
        let ink38 = connected("38", slug: "inkfield", token: "38", perToken: false)
        let tile = connected("86", slug: "tiles", token: "86", perToken: true)
        let response = libraryResponse([ink31, item("u"), ink38, tile])
        let outcome = await store.adopt(host: try host(), response: response)
        #expect(outcome.missing == 4)                                  // every wanted piece, Connected included
        let results = await fillAll(store)
        #expect(results == [.saved, .saved, .saved])                   // ink (once), the upload, tiles/86
        #expect(await counter.count == 4)                              // 2 inkField files + 1 upload + 1 tiles file
        // Both inkField tokens are held by the one bundle; the file content is the Host path it came from.
        let inkDir = try #require(LocalCopyStore.heldBundle(for: ink31, in: dir))
        #expect(LocalCopyStore.heldBundle(for: ink38, in: dir) == inkDir)
        #expect(String(data: try Data(contentsOf: inkDir.appendingPathComponent("lib/p5.js")), encoding: .utf8) == "/collections/inkfield/lib/p5.js")
        #expect(LocalCopyStore.heldBundle(for: tile, in: dir)?.lastPathComponent == "86")
        let counts = LocalCopyStore.counts(for: await store.current, in: dir, filter: web)
        #expect(counts.total == 4 && counts.saved == 4)
        // The default filter still counts uploads only, so tvOS-style readers are unchanged.
        let native = LocalCopyStore.counts(for: await store.current, in: dir)
        #expect(native.total == 1 && native.saved == 1)
        // The seed plays the Connected pieces too.
        let manifest = try #require(await store.current)
        let seed = try #require(LocalCopyStore.seed(from: manifest, in: dir, filter: web))
        #expect(seed.items.map(\.id) == ["31", "u", "38", "86"])
    }

    @Test func aReMirroredFileIsFetchedAgainAndAnUnchangedBundleIsNot() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let version = Version()
        let store = LocalCopyStore(directory: dir, dependencies: deps(listings: { _ in
            let v = version.value
            return self.listing("/collections/inkfield", [("index.html", 5, 1), ("lib/p5.js", 7, Int64(v))])
        }, counter: counter), filter: web)
        let ink = connected("31", slug: "inkfield", token: "31", perToken: false)
        _ = await store.adopt(host: try host(), response: libraryResponse([ink]))
        #expect(await fillAll(store) == [.saved])
        #expect(await counter.count == 2)
        // Same listing: nothing to do (nextMissing finds it held; a direct save says so too).
        #expect(await store.save(ink) == .alreadySaved)
        #expect(await counter.count == 2)
        // The mirror rewrote p5.js: only that file is fetched.
        version.value = 2
        #expect(await store.save(ink) == .saved)
        #expect(await counter.count == 3)
    }

    @Test func aDepartedBundleAgesOutAfterTheGrace() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let clock = TestClock()
        let store = LocalCopyStore(directory: dir, grace: 100, dependencies: deps(listings: { _ in
            self.listing("/collections/inkfield", [("index.html", 5, 1)])
        }, counter: CallCounter(), now: { clock.now }), filter: web)
        let ink = connected("31", slug: "inkfield", token: "31", perToken: false)
        _ = await store.adopt(host: try host(), response: libraryResponse([ink, item("u")]))
        _ = await fillAll(store)
        #expect(LocalCopyStore.heldBundle(for: ink, in: dir) != nil)
        // Leaves the rotation: kept through the grace, gone after.
        _ = await store.adopt(host: try host(), response: libraryResponse([item("u")]))
        #expect(LocalCopyStore.heldBundle(for: ink, in: dir) != nil)
        clock.now = clock.now.addingTimeInterval(101)
        _ = await store.adopt(host: try host(), response: libraryResponse([item("u")]))
        #expect(LocalCopyStore.heldBundle(for: ink, in: dir) == nil)
    }

    @Test func aFailedListingOrFileLeavesTheBundleUnheld() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = LocalCopyStore(directory: dir, dependencies: deps(listings: { _ in nil }, counter: CallCounter()), filter: web)
        let ink = connected("31", slug: "inkfield", token: "31", perToken: false)
        _ = await store.adopt(host: try host(), response: libraryResponse([ink]))
        #expect(await store.save(ink) == .failed)
        #expect(LocalCopyStore.heldBundle(for: ink, in: dir) == nil)
        let manifest = try #require(await store.current)
        #expect(LocalCopyStore.seed(from: manifest, in: dir, filter: web) == nil)
    }

    @Test func offlineKeepsOnlyTheHeldConnectedPieces() {
        let a = connected("a", slug: "inkfield", token: "1", perToken: false)
        let b = connected("b", slug: "tiles", token: "2", perToken: true)
        let r = DisplayResponse(items: [a, item("u"), b], pinnedId: "b")
        let kept = r.droppingConnected(unless: { $0.id == "a" })
        #expect(kept.items.map(\.id) == ["a", "u"])
        #expect(kept.pinnedId == nil)
    }
}

private final class Version: @unchecked Sendable { var value = 1 }
private final class TestClock: @unchecked Sendable { var now = Date(timeIntervalSince1970: 1_000_000) }

import Testing
import Foundation
@testable import DisplayCore

@Suite struct MediaCacheTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oo-cache-\(UUID().uuidString)")
    }

    @Test func downloadsOnceThenServesFromDisk() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let cache = MediaCache(directory: dir) { _ in
            await counter.increment()
            return Data(repeating: 0xAB, count: 1000)
        }
        let url = URL(string: "http://host/uploads/a.jpg")!
        let first = try await cache.localFile(for: url)
        let second = try await cache.localFile(for: url)
        #expect(first == second)
        #expect(await counter.count == 1)                       // fetched once, then served from disk
        #expect(FileManager.default.fileExists(atPath: first.path))
    }

    @Test func purgeTolerantReDownloadsAfterCacheWiped() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let counter = CallCounter()
        let cache = MediaCache(directory: dir) { _ in
            await counter.increment(); return Data(repeating: 1, count: 500)
        }
        let url = URL(string: "http://host/x.png")!
        _ = try await cache.localFile(for: url)
        try FileManager.default.removeItem(at: dir)             // simulate tvOS purging Caches
        _ = try await cache.localFile(for: url)
        #expect(await counter.count == 2)                       // a miss is normal -> re-download
    }

    @Test func evictsLeastRecentlyUsedOverCap() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = MediaCache(directory: dir, capBytes: 2500) { _ in Data(repeating: 7, count: 1000) }
        let a = try await cache.localFile(for: URL(string: "http://h/a")!)
        try await Task.sleep(for: .milliseconds(20))
        _ = try await cache.localFile(for: URL(string: "http://h/b")!)
        try await Task.sleep(for: .milliseconds(20))
        _ = try await cache.localFile(for: URL(string: "http://h/c")!)  // 3rd 1000-byte file over the 2500 cap
        let usage = await cache.usage()
        #expect(usage.bytes <= 2500)
        #expect(!FileManager.default.fileExists(atPath: a.path))        // 'a' (oldest) evicted
    }

    @Test func clearEmptiesTheCache() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let cache = MediaCache(directory: dir) { _ in Data(repeating: 0, count: 100) }
        _ = try await cache.localFile(for: URL(string: "http://h/a")!)
        await cache.clear()
        #expect(await cache.usage().count == 0)
    }
}

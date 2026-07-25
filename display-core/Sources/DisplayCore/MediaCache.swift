import Foundation
import CryptoKit

// A bounded, purge-tolerant on-disk media cache (§9), the native counterpart to
// player/src/folder-cache.js. Pieces are downloaded once and reused across rotation passes; total size
// stays under a byte cap by evicting least-recently-used files. It lives in Caches, which tvOS may
// purge at will, so a miss is normal — the file is simply re-downloaded. A cache is not ownership (§3):
// nothing here is the Library. Injectable `fetch` keeps it testable without a network.

public enum MediaCacheError: Error, Sendable {
    case httpStatus(Int)
}

public actor MediaCache {
    public struct Usage: Sendable, Equatable {
        public let bytes: Int
        public let count: Int
        public let capBytes: Int
    }

    private let directory: URL
    private let capBytes: Int
    private let fetch: @Sendable (URL) async throws -> Data

    public init(directory: URL,
                capBytes: Int = 512 * 1024 * 1024,
                fetch: @escaping @Sendable (URL) async throws -> Data = MediaCache.urlSessionFetch) {
        self.directory = directory
        self.capBytes = capBytes
        self.fetch = fetch
    }

    /// A local file URL for a media URL, downloading it once if absent. Purge-tolerant: if Caches was
    /// wiped, this simply re-downloads.
    public func localFile(for remoteURL: URL) async throws -> URL {
        ensureDirectory()
        let path = cachePath(for: remoteURL)
        if !FileManager.default.fileExists(atPath: path.path) {
            let data = try await fetch(remoteURL)
            try data.write(to: path, options: .atomic)
            enforceCap(keeping: path)
        }
        touch(path) // mark most-recently-used
        return path
    }

    public func usage() -> Usage {
        let files = cachedFiles()
        return Usage(bytes: files.reduce(0) { $0 + $1.size }, count: files.count, capBytes: capBytes)
    }

    public func clear() {
        for file in cachedFiles() { try? FileManager.default.removeItem(at: file.url) }
    }

    // MARK: - Internals

    /// The default fetcher: a plain URLSession GET, failing on a non-2xx status.
    public static let urlSessionFetch: @Sendable (URL) async throws -> Data = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MediaCacheError.httpStatus(http.statusCode)
        }
        return data
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // A stable filename from the URL (SHA-256), keeping the extension so AVPlayer/ImageIO can sniff type.
    private func cachePath(for remoteURL: URL) -> URL {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = remoteURL.pathExtension
        return directory.appendingPathComponent(ext.isEmpty ? hex : "\(hex).\(ext)")
    }

    private func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    }

    private struct Entry { let url: URL; let size: Int; let modified: Date }

    private func cachedFiles() -> [Entry] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Entry(url: url, size: values.fileSize ?? 0,
                         modified: values.contentModificationDate ?? .distantPast)
        }
    }

    // Evict least-recently-used files until under the cap, never the just-written file.
    private func enforceCap(keeping: URL?) {
        var files = cachedFiles()
        var total = files.reduce(0) { $0 + $1.size }
        guard total > capBytes else { return }
        files.sort { $0.modified < $1.modified } // oldest first
        for file in files where total > capBytes {
            if file.url == keeping { continue }
            try? FileManager.default.removeItem(at: file.url)
            total -= file.size
        }
    }
}

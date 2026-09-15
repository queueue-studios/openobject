import Foundation

// Ties the cache and decoder together (§9): fetch a renderable item's bytes (cached, downloaded once)
// and turn them into ready-to-display media. Video is the easy case — it hands AVPlayer a local file
// URL, which streams and buffers itself. A one-item `prefetch` lets the driver warm the NEXT piece
// before the current one ends, so a crossfade has something ready.

public enum RenderableMedia: Sendable {
    case still(SendableImage)        // a decoded, panel-sized bitmap
    case animated(AnimatedImage)     // decode-on-demand frames
    case video(URL)                  // a local file URL for AVPlayer (Phase C)
}

public enum MediaPipelineError: Error, Sendable {
    case badURL(String)
    case undecodable(String)
}

public struct MediaPipeline: Sendable {
    /// A durable local file for an item on a Host, if one is held (the iPad's local copy, HANDOFF §17), else
    /// nil. Consulted before the cache. Host-scoped: a path like /uploads/IMG_0001.jpg can exist on two Hosts.
    public typealias LocalFileLookup = @Sendable (Host, DisplayItem) async -> URL?

    private let cache: MediaCache
    private let maxPixel: Int
    private let localFile: LocalFileLookup?

    /// - Parameter maxPixel: the longest-side cap for decoded stills and animated frames. Phase C sets
    ///   this to the display's pixel size; the default is a safe 4K-ish cap.
    /// - Parameter localFile: an optional durable source checked before the cache (the iPad's local copy);
    ///   nil (tvOS, tests) means cache-then-network as before.
    public init(cache: MediaCache, maxPixel: Int = 2160, localFile: LocalFileLookup? = nil) {
        self.cache = cache
        self.maxPixel = maxPixel
        self.localFile = localFile
    }

    /// The host-relative media path for an item: its `src` (folder items) or /uploads/<filename> (uploads),
    /// matching display.js (`item.src || '/uploads/' + item.filename`). Also the local copy's key for the
    /// piece, so a Host whose LAN address changes keeps its copy.
    public static func mediaPath(for item: DisplayItem) -> String {
        item.src ?? "/uploads/\(item.filename ?? "")"
    }

    /// The absolute media URL for an item on a Host: `mediaPath` resolved against the Host's baseURL.
    public static func mediaURL(for item: DisplayItem, on host: Host) -> URL? {
        URL(string: mediaPath(for: item), relativeTo: host.baseURL)?.absoluteURL
    }

    /// Instance form of `mediaURL(for:on:)`, kept for the stage and tests.
    public func mediaURL(for item: DisplayItem, on host: Host) -> URL? {
        Self.mediaURL(for: item, on: host)
    }

    /// Fetch (via the cache) and decode an item into ready-to-display media. An animated piece that
    /// fails to open as a sequence falls back to a still (its first frame), so art never fails hard.
    public func load(_ item: DisplayItem, from host: Host) async throws -> RenderableMedia {
        let file: URL
        if let localFile, let held = await localFile(host, item) {
            file = held                                          // the local copy: no network at all
        } else {
            guard let url = mediaURL(for: item, on: host) else { throw MediaPipelineError.badURL(item.id) }
            file = try await cache.localFile(for: url)
        }
        if item.kind == .video { return .video(file) }           // AVPlayer streams the local file

        let data = try Data(contentsOf: file)
        if item.kind == .animated, let animated = AnimatedImage(data: data, maxPixel: maxPixel) {
            return .animated(animated)
        }
        guard let still = ImageDecoder.decodeStill(data, maxPixel: maxPixel) else {
            throw MediaPipelineError.undecodable(item.id)
        }
        return .still(still)
    }

    /// Warm the cache for an item — the driver calls this for the NEXT piece so a crossfade is ready.
    /// Best-effort: errors are swallowed (a failed prefetch just means a cache miss at play time).
    public func prefetch(_ item: DisplayItem, from host: Host) async {
        if let localFile, await localFile(host, item) != nil { return }   // already held: nothing to warm
        guard let url = mediaURL(for: item, on: host) else { return }
        _ = try? await cache.localFile(for: url)
    }
}

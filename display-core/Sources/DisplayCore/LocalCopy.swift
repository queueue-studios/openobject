import Foundation
import CryptoKit
import Observation

// The local copy (HANDOFF §17 "Offline / portable playback", design settled 2026-09-15): a durable, automatic
// mirror of the remembered Host's CURRENT rotation, so an iPad or iPhone keeps playing with the Host gone and
// can be carried away from the network entirely. Always on, no switch. It is a mirror, not a library: the Host
// stays the source of truth, nothing here can add or remove art, and the copy reconciles to the Host on every
// successful poll. One Host at a time, the remembered one; a different Host drops the previous copy.
//
// It lives in DisplayCore (Foundation-only) so it unit-tests headlessly on macOS. Only the iPad/iPhone app
// constructs one: tvOS has no non-purgeable storage to hold it (§17), and the tvOS app is untouched.
//
// Layout, under a directory in Application Support (never purged by iOS; excluded from iCloud backup, since
// the art is re-fetchable from the Host):
//   manifest.json          the Host, the last successful /api/display response, departed-file dates
//   media/<sha256>.<ext>   one file per held piece, keyed by the HOST-RELATIVE media path
// Keying by path rather than absolute URL means a Host whose LAN address changes (DHCP) keeps its copy; the
// copy is per-Host anyway, and lookups are Host-scoped.
//
// Space: as much as the rotation needs, never past a free-space reserve, no fixed ceiling. The reserve is one
// tenth of the volume with a 5 GB floor, checked before every file; a piece that would breach it is skipped
// and the fill moves on. Pieces that left the rotation ("departed") are kept for a grace period, so a brief
// Pin (which collapses the rotation to one piece on the wire) does not churn gigabytes, and they are the
// first to go when a wanted piece needs the room.

/// What the copy holds right now, for the stage overlay and the picker (§17).
public struct LocalCopyStatus: Sendable, Equatable {
    /// Renderable pieces in the Host's current rotation.
    public var total: Int
    /// Of those, held on this device.
    public var saved: Int
    /// Wanted pieces held back by the free-space reserve in the last fill pass.
    public var skippedForSpace: Int
    /// A fill pass is running.
    public var isSaving: Bool

    public init(total: Int, saved: Int, skippedForSpace: Int, isSaving: Bool) {
        self.total = total
        self.saved = saved
        self.skippedForSpace = skippedForSpace
        self.isSaving = isSaving
    }

    /// Something is held: the picker offers the copy, and an offline launch can play it.
    public var hasCopy: Bool { saved > 0 }
    /// Everything in the rotation is held.
    public var isComplete: Bool { total > 0 && saved == total }

    public static let empty = LocalCopyStatus(total: 0, saved: 0, skippedForSpace: 0, isSaving: false)
}

/// Free and total bytes on the volume holding the copy.
public struct VolumeSpace: Sendable, Equatable {
    public let available: Int64
    public let total: Int64
    public init(available: Int64, total: Int64) {
        self.available = available
        self.total = total
    }
}

/// What is written to manifest.json: enough for an offline launch to know the Host, the rotation (items,
/// order, mode, duration, Fit per piece), and which held files are on their way out.
public struct LocalCopyManifest: Codable, Sendable, Equatable {
    public var host: Host
    public var response: DisplayResponse
    public var savedAt: Date
    /// Held files no longer in the rotation, keyed by file name, with when each was first seen departed.
    public var departed: [String: Date]

    public init(host: Host, response: DisplayResponse, savedAt: Date, departed: [String: Date] = [:]) {
        self.host = host
        self.response = response
        self.savedAt = savedAt
        self.departed = departed
    }
}

public enum LocalCopySaveResult: Sendable, Equatable {
    case saved
    case alreadySaved
    /// Held back by the free-space reserve (after departed pieces were purged to try to make room).
    case skippedForSpace
    /// The download failed (the Host went away mid-fill, a bad status). Retried on a later pass.
    case failed
}

public enum LocalCopyError: Error, Sendable, Equatable {
    case notHTTP
    case httpStatus(Int)
}

/// The on-disk store: the manifest, the held files, the reserve. An actor, since it owns files and the
/// coordinator drives it from the main actor while downloads run.
public actor LocalCopyStore {
    /// The store's outside world, injectable so the reserve, the grace period, and downloads unit-test
    /// without a network or a real volume.
    public struct Dependencies: Sendable {
        /// The byte size of a media URL (an HTTP HEAD), or nil if the Host does not say.
        public var fetchSize: @Sendable (URL) async throws -> Int64?
        /// Download a media URL to a file path (replacing any file there).
        public var download: @Sendable (URL, URL) async throws -> Void
        /// Free and total bytes for the volume holding a directory, or nil if unknown (then never blocks).
        public var space: @Sendable (URL) -> VolumeSpace?
        public var now: @Sendable () -> Date

        public init(fetchSize: @escaping @Sendable (URL) async throws -> Int64?,
                    download: @escaping @Sendable (URL, URL) async throws -> Void,
                    space: @escaping @Sendable (URL) -> VolumeSpace?,
                    now: @escaping @Sendable () -> Date = { Date() }) {
            self.fetchSize = fetchSize
            self.download = download
            self.space = space
            self.now = now
        }

        public static let live = Dependencies(fetchSize: LocalCopyStore.urlSessionSize,
                                              download: LocalCopyStore.urlSessionDownload,
                                              space: LocalCopyStore.volumeSpace)
    }

    /// How long a departed piece is kept before deletion. A day covers an evening's Pin.
    public static let defaultGrace: TimeInterval = 24 * 60 * 60
    /// The smallest reserve, for small devices.
    public static let reserveFloor: Int64 = 5_000_000_000

    /// Free space the copy never eats into: one tenth of the volume, with the floor.
    public static func reserveBytes(forVolumeOf total: Int64) -> Int64 {
        max(total / 10, reserveFloor)
    }

    public nonisolated let directory: URL
    private nonisolated let mediaDir: URL
    private let deps: Dependencies
    private let grace: TimeInterval
    private var manifest: LocalCopyManifest?

    public init(directory: URL, grace: TimeInterval = LocalCopyStore.defaultGrace,
                dependencies: Dependencies = .live) {
        self.directory = directory
        self.mediaDir = Self.mediaDirectory(in: directory)
        self.grace = grace
        self.deps = dependencies
        self.manifest = Self.readManifest(in: directory)
    }

    // MARK: - Disk layout (nonisolated so a launch can read the copy synchronously)

    public nonisolated static func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent("manifest.json")
    }

    public nonisolated static func mediaDirectory(in directory: URL) -> URL {
        directory.appendingPathComponent("media", isDirectory: true)
    }

    public nonisolated static func readManifest(in directory: URL) -> LocalCopyManifest? {
        guard let data = try? Data(contentsOf: manifestURL(in: directory)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LocalCopyManifest.self, from: data)
    }

    /// The file name a piece is held under: SHA-256 of its host-relative media path, keeping the extension
    /// so AVPlayer/ImageIO can sniff the type (the MediaCache scheme, keyed by path instead of absolute URL).
    public nonisolated static func fileName(for item: DisplayItem) -> String {
        let path = MediaPipeline.mediaPath(for: item)
        let digest = SHA256.hash(data: Data(path.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let ext = (path as NSString).pathExtension
        return ext.isEmpty ? hex : "\(hex).\(ext)"
    }

    /// The pieces the copy wants: the renderable ones, in rotation order. Connected pieces are skipped here
    /// exactly as the engine skips them (§2, §6).
    public nonisolated static func wantedItems(in response: DisplayResponse) -> [DisplayItem] {
        response.items.filter { $0.isRenderable() }
    }

    /// The held file for a piece, or nil if not held.
    public nonisolated static func heldFile(for item: DisplayItem, in directory: URL) -> URL? {
        let url = mediaDirectory(in: directory).appendingPathComponent(fileName(for: item))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// How much of a manifest's rotation is held.
    public nonisolated static func counts(for manifest: LocalCopyManifest?, in directory: URL) -> (total: Int, saved: Int) {
        guard let manifest else { return (0, 0) }
        let wanted = wantedItems(in: manifest.response)
        return (wanted.count, wanted.filter { heldFile(for: $0, in: directory) != nil }.count)
    }

    /// A rotation to play with no Host: the manifest's response cut to the pieces actually held, and awake
    /// (offline ignores the Sleep schedule, §17). Nil if nothing is held. A Pin whose piece is not held is
    /// dropped rather than collapsing the rotation to nothing.
    public nonisolated static func seed(from manifest: LocalCopyManifest, in directory: URL) -> DisplayResponse? {
        let held = wantedItems(in: manifest.response).filter { heldFile(for: $0, in: directory) != nil }
        guard !held.isEmpty else { return nil }
        let r = manifest.response
        let pin = held.contains { $0.id == r.pinnedId } ? r.pinnedId : nil
        return DisplayResponse(items: held, durationMs: r.durationMs, mode: r.mode, pinnedId: pin,
                               asleep: false, source: r.source)
    }

    // MARK: - The copy

    public var current: LocalCopyManifest? { manifest }

    public struct AdoptOutcome: Sendable, Equatable {
        public let manifest: LocalCopyManifest
        /// Wanted pieces not yet held.
        public let missing: Int
        /// The wanted set in order; a change starts a fresh fill pass.
        public let signature: String
    }

    /// Fold a successful poll into the copy: adopt the Host (a different Host drops the previous copy), record
    /// the response as the manifest, and age out departed pieces. Cheap enough for every poll.
    public func adopt(host: Host, response: DisplayResponse) -> AdoptOutcome {
        if let manifest, manifest.host.id != host.id { removeEverything() }   // one Host at a time (§17)
        ensureDirectories()
        let now = deps.now()
        let wantedNames = Self.wantedItems(in: response).map(Self.fileName(for:))
        let wantedSet = Set(wantedNames)
        var departed = manifest?.departed ?? [:]

        // Departed: held but no longer in the rotation. Dated when first noticed; deleted once past the grace.
        for name in heldNames() where !wantedSet.contains(name) {
            if departed[name] == nil { departed[name] = now }
        }
        for name in wantedSet { departed[name] = nil }                          // returned to the rotation
        for (name, since) in departed where now.timeIntervalSince(since) >= grace {
            try? FileManager.default.removeItem(at: mediaURL(name))
            departed[name] = nil
        }
        let held = heldNames()
        departed = departed.filter { held.contains($0.key) }                  // a file gone by other means

        let changed = manifest?.response != response
        let next = LocalCopyManifest(host: host, response: response,
                                     savedAt: changed ? now : (manifest?.savedAt ?? now), departed: departed)
        if next != manifest {
            manifest = next
            writeManifest()
        }
        let missing = wantedNames.filter { !held.contains($0) }.count
        return AdoptOutcome(manifest: next, missing: missing, signature: wantedNames.joined(separator: "|"))
    }

    /// The first wanted piece not held and not in `attempted`, in rotation order; nil when the pass is done.
    public func nextMissing(excluding attempted: Set<String>) -> DisplayItem? {
        guard let manifest else { return nil }
        let held = heldNames()
        return Self.wantedItems(in: manifest.response).first { item in
            let name = Self.fileName(for: item)
            return !held.contains(name) && !attempted.contains(name)
        }
    }

    /// Download one piece into the copy, honoring the reserve. Departed pieces are purged first when room is
    /// short. A download that completes after the copy was cleared or re-homed is discarded.
    public func save(_ item: DisplayItem) async -> LocalCopySaveResult {
        guard let host = manifest?.host, let url = MediaPipeline.mediaURL(for: item, on: host) else { return .failed }
        let name = Self.fileName(for: item)
        let destination = mediaURL(name)
        if FileManager.default.fileExists(atPath: destination.path) { return .alreadySaved }
        ensureDirectories()

        let size = (try? await deps.fetchSize(url)) ?? nil
        if !fits(size ?? 0) {
            purgeDeparted()
            if !fits(size ?? 0) { return .skippedForSpace }
        }

        let part = mediaURL(name + ".part")
        try? FileManager.default.removeItem(at: part)
        do {
            try await deps.download(url, part)
        } catch {
            try? FileManager.default.removeItem(at: part)
            return .failed
        }
        guard manifest?.host.id == host.id else {                     // cleared or re-homed meanwhile
            try? FileManager.default.removeItem(at: part)
            return .failed
        }
        if size == nil, !fits(0) {                                     // size unknown up front: verify after
            try? FileManager.default.removeItem(at: part)
            purgeDeparted()
            return .skippedForSpace
        }
        do {
            try FileManager.default.moveItem(at: part, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: part)
            return .failed
        }
        return .saved
    }

    /// Drop the whole copy: the manifest and every held file.
    public func clear() {
        removeEverything()
        manifest = nil
    }

    // MARK: - Internals

    private func fits(_ size: Int64) -> Bool {
        guard let space = deps.space(directory) else { return true }      // unknown volume: never block
        return space.available - size >= Self.reserveBytes(forVolumeOf: space.total)
    }

    private func purgeDeparted() {
        guard var manifest, !manifest.departed.isEmpty else { return }
        for name in manifest.departed.keys { try? FileManager.default.removeItem(at: mediaURL(name)) }
        manifest.departed = [:]
        self.manifest = manifest
        writeManifest()
    }

    private nonisolated func mediaURL(_ name: String) -> URL {
        mediaDir.appendingPathComponent(name)
    }

    private nonisolated func heldNames() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: mediaDir.path)) ?? []
        return Set(names.filter { !$0.hasSuffix(".part") })
    }

    private func ensureDirectories() {
        try? FileManager.default.createDirectory(at: mediaDir, withIntermediateDirectories: true)
        // Re-fetchable from the Host, and a multi-gigabyte backup would be rude.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var top = directory
        try? top.setResourceValues(values)
    }

    private func writeManifest() {
        guard let manifest else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(manifest) {
            try? data.write(to: Self.manifestURL(in: directory), options: .atomic)
        }
    }

    private func removeEverything() {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Live dependencies

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30              // inactivity, not total: a big video may take a while
        config.timeoutIntervalForResource = 6 * 60 * 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    public static let urlSessionSize: @Sendable (URL) async throws -> Int64? = { url in
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LocalCopyError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw LocalCopyError.httpStatus(http.statusCode) }
        return http.expectedContentLength >= 0 ? http.expectedContentLength : nil
    }

    public static let urlSessionDownload: @Sendable (URL, URL) async throws -> Void = { url, destination in
        let (temp, response) = try await session.download(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            try? FileManager.default.removeItem(at: temp)
            throw LocalCopyError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temp, to: destination)
    }

    public static let volumeSpace: @Sendable (URL) -> VolumeSpace? = { directory in
        // "Important usage" counts space the OS could free by purging its own caches, the honest number for
        // "room for the owner's art" on iOS. tvOS lacks that key (it never holds a copy anyway, §17), so the
        // shared package falls back to the plain figure there just to compile.
        #if os(tvOS)
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityKey, .volumeTotalCapacityKey]
        guard let values = try? directory.resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacity,
              let total = values.volumeTotalCapacity else { return nil }
        return VolumeSpace(available: Int64(available), total: Int64(total))
        #else
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? directory.resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return VolumeSpace(available: available, total: Int64(total))
        #endif
    }
}

/// The app-facing coordinator: observable status for the overlay and the picker, the fill passes, and the
/// synchronous reads a launch needs (is there a copy for the remembered Host, and what does it play).
@MainActor
@Observable
public final class LocalCopy {
    /// The Host whose rotation is held (nil until a Host has been polled successfully, or after `clear`).
    public private(set) var host: Host?
    public private(set) var status: LocalCopyStatus = .empty

    @ObservationIgnored private let store: LocalCopyStore
    @ObservationIgnored private let directory: URL
    @ObservationIgnored private var manifest: LocalCopyManifest?
    @ObservationIgnored private var fill: Task<Void, Never>?
    @ObservationIgnored private var passID = UUID()
    @ObservationIgnored private var lastPassSignature = ""
    @ObservationIgnored private var lastPassAt = Date.distantPast
    @ObservationIgnored private var lastPassIncomplete = false
    @ObservationIgnored private let retryInterval: TimeInterval

    /// - Parameter retryInterval: how long after an incomplete pass (space, or a failed download) the next
    ///   successful poll may start another, so a full disk is not re-probed every five seconds.
    public init(directory: URL, grace: TimeInterval = LocalCopyStore.defaultGrace,
                dependencies: LocalCopyStore.Dependencies = .live, retryInterval: TimeInterval = 30) {
        self.directory = directory
        self.retryInterval = retryInterval
        store = LocalCopyStore(directory: directory, grace: grace, dependencies: dependencies)
        manifest = LocalCopyStore.readManifest(in: directory)          // synchronous: a launch decides on it
        host = manifest?.host
        let counts = LocalCopyStore.counts(for: manifest, in: directory)
        status = LocalCopyStatus(total: counts.total, saved: counts.saved, skippedForSpace: 0, isSaving: false)
    }

    /// What to play for a Host with no network: its held rotation, or nil if this is not the held Host or
    /// nothing is held yet.
    public func seed(for host: Host) -> DisplayResponse? {
        guard let manifest, manifest.host.id == host.id else { return nil }
        return LocalCopyStore.seed(from: manifest, in: directory)
    }

    /// The held file for a piece on a Host (the pipeline's local source), Host-scoped.
    public func localFile(host: Host, item: DisplayItem) -> URL? {
        guard let manifest, manifest.host.id == host.id else { return nil }
        return LocalCopyStore.heldFile(for: item, in: directory)
    }

    /// Feed a successful poll to the copy. The app calls this for every real Host it polls (never the
    /// Gallery); it reconciles the manifest and starts a fill pass when pieces are missing.
    public func observe(host: Host, response: DisplayResponse) async {
        let outcome = await store.adopt(host: host, response: response)
        manifest = outcome.manifest
        self.host = outcome.manifest.host
        refreshCounts()
        startFillIfNeeded(outcome)
    }

    /// Drop the copy (a different Host was chosen, §17). Immediate for the UI; the files follow.
    public func clear() {
        fill?.cancel()
        fill = nil
        manifest = nil
        host = nil
        status = .empty
        lastPassSignature = ""
        lastPassIncomplete = false
        Task { await store.clear() }
    }

    // MARK: - Fill passes

    private func refreshCounts(saving: Bool? = nil, skipped: Int? = nil) {
        let counts = LocalCopyStore.counts(for: manifest, in: directory)
        status = LocalCopyStatus(total: counts.total, saved: counts.saved,
                                 skippedForSpace: skipped ?? status.skippedForSpace,
                                 isSaving: saving ?? status.isSaving)
    }

    private func startFillIfNeeded(_ outcome: LocalCopyStore.AdoptOutcome) {
        guard fill == nil, outcome.missing > 0 else { return }
        let fresh = outcome.signature != lastPassSignature
        let retryDue = lastPassIncomplete && Date().timeIntervalSince(lastPassAt) >= retryInterval
        guard fresh || retryDue else { return }
        lastPassSignature = outcome.signature
        status.isSaving = true
        status.skippedForSpace = 0
        let id = UUID()
        passID = id
        fill = Task { [weak self, store] in
            var attempted = Set<String>()
            var skipped = 0
            var failed = 0
            // Ahead of playback, in rotation order; the wanted set is re-read each step so a rotation edited
            // mid-pass is honored.
            while !Task.isCancelled, let item = await store.nextMissing(excluding: attempted) {
                attempted.insert(LocalCopyStore.fileName(for: item))
                switch await store.save(item) {
                case .skippedForSpace: skipped += 1
                case .failed: failed += 1
                case .saved, .alreadySaved: break
                }
                guard !Task.isCancelled else { return }
                self?.refreshCounts(saving: true, skipped: skipped)
            }
            guard !Task.isCancelled else { return }
            self?.finishPass(id, skipped: skipped, failed: failed)
        }
    }

    private func finishPass(_ id: UUID, skipped: Int, failed: Int) {
        guard id == passID else { return }                                 // a superseded pass: ignore
        fill = nil
        lastPassAt = Date()
        lastPassIncomplete = skipped > 0 || failed > 0
        refreshCounts(saving: false, skipped: skipped)
    }
}

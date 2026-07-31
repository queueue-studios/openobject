import Foundation
import Observation
import DisplayCore

// The iPad app's top-level state: which screen is up (the Host picker, or the art stage for a chosen
// Host) plus the machinery each needs. Mirrors the tvOS AppModel (it is input-agnostic: Foundation +
// DisplayCore, no UIKit/focus), so the two apps coordinate discovery, the remembered Host, and the Sound
// setting identically. G2 uses the remembered-Host path to open straight to art; the touch picker that
// drives discovery/manual entry arrives in G3.
//
// (Currently a near-verbatim copy of tv-app's AppModel. If it stays identical through G4 it can move to a
// shared package, same pattern as the views; it is kept per-app for now since the touch exit/orientation
// work may add iPad-specific state.)
@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case picker
        case display(Host)
    }

    private(set) var route: Route = .picker

    let discovery = HostDiscovery()
    let player = RotationPlayer()
    let pipeline: MediaPipeline

    // Manual-entry field + its error, and the "still looking" flag that drives the waiting copy (§13).
    var manualAddress = ""
    var manualError: String?
    private(set) var scanning = false

    /// Whether the public OpenObject Gallery answered its last probe: nil while checking, then true/false.
    /// The picker offers the Gallery in its empty state ONLY when this is true, so a no-internet / CDN-down
    /// state falls back to the plain "No Hosts found" copy instead of a dead button (§12/§13).
    private(set) var galleryReachable: Bool?

    // The app-owned Sound setting (§10): whether this device plays a scored video's audio. Sticky and
    // default On; the device's own volume/mute is the loudness control above it. Only uploaded videos can
    // carry audio here (Connected scored pieces are skipped), so this gates exactly that.
    var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: Self.soundKey) }
    }
    private static let soundKey = "openobject.soundOn"

    @ObservationIgnored private let store: HostStore
    @ObservationIgnored private var scanFloor: Task<Void, Never>?
    @ObservationIgnored private var galleryProbe: Task<Void, Never>?

    init(store: HostStore = UserDefaultsHostStore()) {
        self.store = store
        soundOn = (UserDefaults.standard.object(forKey: Self.soundKey) as? Bool) ?? true
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        pipeline = MediaPipeline(cache: MediaCache(directory: caches.appendingPathComponent("OOMedia")),
                                 maxPixel: 3840)
        // Open straight to art if a Host is remembered from a previous launch (§5).
        if let remembered = store.loadDefaultHost() {
            route = .display(remembered)
            player.start(host: remembered)
        }
    }

    /// The live discovery list, sorted and deduplicated (observed by the picker).
    var hosts: [Host] { discovery.hosts }

    /// Begin browsing when the picker is showing. Idempotent.
    func startDiscoveryIfPicking() {
        guard route == .picker else { return }
        discovery.start()
        probeGallery()
        scanning = true
        // Hold "Looking…" briefly so a Host about to resolve doesn't flash the empty copy first (§13).
        scanFloor?.cancel()
        scanFloor = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.scanning = false
        }
    }

    /// Re-kick discovery from scratch. Needed on first launch: the NWBrowser started before the Local
    /// Network permission prompt does not pick up the grant, so once the user allows it (the app becomes
    /// active again) we restart browsing and the Host appears without a manual relaunch. Also serves as a
    /// manual rescan. No-op unless the picker is showing.
    func rescan() {
        guard route == .picker else { return }
        discovery.stop()
        discovery.start()
        probeGallery()
        scanning = true
        scanFloor?.cancel()
        scanFloor = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.scanning = false
        }
    }

    /// Leave the art stage for the picker. Stops playback so nothing polls in the background; the picker
    /// restarts discovery when it appears.
    func showPicker() {
        player.stop()
        clearManualEntry()
        route = .picker
    }

    /// Drop any half-typed address + its error, so a stale draft never lingers.
    func clearManualEntry() {
        manualAddress = ""
        manualError = nil
    }

    /// Choose a Host: remember it, stop browsing, and switch to its art.
    func select(_ host: Host) {
        store.saveDefaultHost(host)
        discovery.stop()
        scanFloor?.cancel()
        clearManualEntry()
        player.start(host: host)
        route = .display(host)
    }

    /// Probe the public OpenObject Gallery (a short-timeout GET of its /api/display) so the picker only
    /// offers it when it will actually work (§13). Runs alongside discovery; the result drives the
    /// empty-state row. No-op-safe to call repeatedly (each call supersedes the last probe).
    func probeGallery() {
        galleryProbe?.cancel()
        galleryReachable = nil
        galleryProbe = Task { [weak self] in
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 3
            config.waitsForConnectivity = false
            let client = DisplayClient(session: URLSession(configuration: config))
            let ok = (try? await client.fetchDisplay(from: .gallery)) != nil
            guard !Task.isCancelled else { return }
            self?.galleryReachable = ok
        }
    }

    /// Connect to the public OpenObject Gallery WITHOUT remembering it (§12): unlike select(host) it saves
    /// no default Host, so the next launch returns to the picker and re-discovers the owner's real frame
    /// rather than reopening the Gallery. Offered only from the probe-gated empty-state row.
    func connectToGallery() {
        discovery.stop()
        scanFloor?.cancel()
        galleryProbe?.cancel()
        clearManualEntry()
        player.start(host: .gallery)
        route = .display(.gallery)
    }

    /// Connect to a typed address (§5). A malformed entry, or one no Host answers, is a plain error (§13)
    /// rather than a silent dead end.
    func submitManualEntry() async {
        manualError = nil
        let raw = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = Host.manualEntry(raw) else {
            manualError = "Enter an address like 192.168.1.10 or openobject.local."
            return
        }
        do {
            _ = try await DisplayClient().fetchDisplay(from: host)
            select(host)
        } catch {
            manualError = "No Host answered at that address."
        }
    }
}

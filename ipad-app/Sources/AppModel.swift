import Foundation
import Observation
import DisplayCore

// The iPad app's top-level state: which screen is up (the Host picker, or the art stage for a chosen
// Host) plus the machinery each needs. Mirrors the tvOS AppModel (it is input-agnostic: Foundation +
// DisplayCore, no UIKit/focus), so the two apps coordinate discovery, the remembered Host, and the Sound
// setting identically. G2 uses the remembered-Host path to open straight to art; the touch picker that
// drives discovery/manual entry arrives in G3.
//
// It diverged from tv-app's AppModel with the local copy (HANDOFF §17, 2026-09-15): this app holds a durable
// mirror of the remembered Host's rotation, which tvOS cannot (no non-purgeable storage), so the two models
// stay per-app rather than shared.
@MainActor
@Observable
final class AppModel {
    enum Route: Equatable {
        case picker
        case display(Host)
    }

    private(set) var route: Route = .picker

    let discovery = HostDiscovery()
    let player: RotationPlayer
    let pipeline: MediaPipeline
    /// The local copy (§17): a durable, automatic mirror of the remembered Host's rotation, always on, no
    /// switch. It feeds the stage overlay's status and the picker's "Local copy" row, and seeds the stage when
    /// the Host is not answering, so opening the app is the whole offline gesture.
    let localCopy: LocalCopy

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
    @ObservationIgnored private var connectWatchdog: Task<Void, Never>?

    init(store: HostStore = UserDefaultsHostStore()) {
        self.store = store
        soundOn = (UserDefaults.standard.object(forKey: Self.soundKey) as? Bool) ?? true
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let localCopy = LocalCopy(directory: support.appendingPathComponent("OpenObject/LocalCopy", isDirectory: true))
        self.localCopy = localCopy
        // A held piece is read straight from the copy, no network at all; anything else goes through the
        // purgeable cache exactly as before.
        pipeline = MediaPipeline(cache: MediaCache(directory: caches.appendingPathComponent("OOMedia")),
                                 maxPixel: 3840,
                                 localFile: { host, item in await localCopy.localFile(host: host, item: item) })
        // Every successful poll of a real Host also feeds the local copy (§17). The Gallery is never saved:
        // choosing it is non-persisting, it is public and online by nature, and it is demo art, not the owner's.
        let client = DisplayClient()
        player = RotationPlayer(fetch: { host in
            let response = try await client.fetchDisplay(from: host)
            if host.id != Host.gallery.id { await localCopy.observe(host: host, response: response) }
            return response
        })
        player.wakesWhenHostUnreachable = true          // offline ignores the Sleep schedule (§17)
        // Open straight to art if a Host is remembered from a previous launch (§5). With a local copy of that
        // Host the art plays at once and the Host folds in if it answers: no Connecting beat, no watchdog.
        if let remembered = store.loadDefaultHost() {
            route = .display(remembered)
            if let seed = localCopy.seed(for: remembered) {
                player.start(host: remembered, seed: seed)
            } else {
                player.start(host: remembered)
                startRememberedHostWatchdog()
            }
        }
    }

    /// The live discovery list, sorted and deduplicated (observed by the picker).
    var hosts: [Host] { discovery.hosts }

    /// The Host whose rotation this device holds, offered as a picker row ONLY while that Host is not on the
    /// network (§17): a live row plays the same art and refreshes the copy, so one name never appears twice.
    /// A manually-typed Host is never discovered, so its row simply stays; tapping it still connects live if
    /// the Host answers. The picker places it after the live Hosts and before the Gallery.
    var localCopyRow: Host? {
        guard localCopy.status.hasCopy, let held = localCopy.host else { return nil }
        let live = hosts.contains { $0.id == held.id || $0.baseURL == held.baseURL }
        return live ? nil : held
    }

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
        connectWatchdog?.cancel()
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
        connectWatchdog?.cancel()
        clearManualEntry()
        // One local copy at a time, the remembered Host's (§17): a different Host drops the previous copy now.
        if let held = localCopy.host, held.id != host.id { localCopy.clear() }
        // A held Host that is not answering plays from its copy at once (the picker's "Local copy" row).
        player.start(host: host, seed: localCopy.seed(for: host))
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
        connectWatchdog?.cancel()
        clearManualEntry()
        player.start(host: .gallery)
        route = .display(.gallery)
    }

    /// Cold-launch recovery: when the app opens straight to a remembered Host that turns out to be gone,
    /// don't sit on "Connecting…" forever. If the Host hasn't answered within a short grace period (and has
    /// never connected this session), fall back to the picker, which discovers Hosts and offers the Gallery.
    /// A Host that connects and later drops still holds its last frame (§16); this covers only the
    /// never-connected launch case, so a real Host that is simply slow to boot still gets picked up (either
    /// here, or by discovery once the picker is showing).
    private func startRememberedHostWatchdog() {
        connectWatchdog?.cancel()
        connectWatchdog = Task { [weak self] in
            for _ in 0..<16 {                                    // ~8s, checked every 0.5s
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                if self.player.hasConnected { return }           // connected in time: stay on the art
                guard case .display = self.route else { return }  // user already moved on
            }
            guard let self, !Task.isCancelled,
                  case .display = self.route, !self.player.hasConnected else { return }
            self.showPicker()                                    // never answered: recover to the picker
        }
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

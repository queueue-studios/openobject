import Foundation
import Observation
import DisplayCore

// The tvOS app's top-level state: which screen is up (the Host picker, or the art stage for a chosen
// Host) plus the machinery each needs. It replaces C3's OO_HOST stopgap with the real flow (§5): Bonjour
// discovery, manual address entry, and a remembered default Host that opens straight to art next launch.
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
    /// True while a typed address is being probed (E24): the picker disables Connect and shows progress on
    /// it, so the button can never look dead. The probe itself is capped at `probeTimeout` seconds.
    private(set) var connecting = false

    /// Whether the public OpenObject Gallery answered its last probe: nil while checking, then true/false.
    /// The picker offers the Gallery in its empty state ONLY when this is true, so a no-internet / CDN-down
    /// state falls back to the plain "No Hosts found" copy instead of a dead button (§12/§13).
    private(set) var galleryReachable: Bool?

    // The app-owned Sound setting (§10): whether this Apple TV plays a scored video's audio. Sticky and
    // default On; the TV's own volume/mute is the loudness control above it. Only uploaded videos can
    // carry audio on tvOS (Connected scored pieces are skipped there), so this gates exactly that.
    var soundOn: Bool {
        didSet { UserDefaults.standard.set(soundOn, forKey: Self.soundKey) }
    }
    private static let soundKey = "openobject.soundOn"

    @ObservationIgnored private let store: HostStore
    @ObservationIgnored private var scanFloor: Task<Void, Never>?
    @ObservationIgnored private var galleryProbe: Task<Void, Never>?
    @ObservationIgnored private var connectWatchdog: Task<Void, Never>?
    @ObservationIgnored private var rebrowse: Task<Void, Never>?

    /// How long a typed address gets to answer before "No Host answered" (E24). `URLSession.shared` would
    /// allow sixty seconds, which read as a Connect button that did nothing (HANDOFF §17); this is the
    /// Siri Remote's version of the same dead minute.
    private static let probeTimeout: TimeInterval = 8
    /// How often discovery is restarted while the picker shows an empty list (E25). A Bonjour browse can
    /// die silently (a Local Network permission toggle kills the one in flight), and the only restart used
    /// to be leaving and re-entering the app; this makes the picker recover on its own, with no UI.
    private static let rebrowseInterval: Duration = .seconds(15)

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
            startRememberedHostWatchdog()
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
        startRebrowse()
    }

    /// While the picker is up with nothing found, restart the browse every `rebrowseInterval` (E25). Silent:
    /// it never touches `scanning`, so the waiting copy does not flicker, and the Gallery is only re-probed
    /// when its last probe failed, so an offered row never blinks out while it is re-checked. Stops itself
    /// the moment a Host appears or the picker is left; idempotent while running.
    private func startRebrowse() {
        guard rebrowse == nil else { return }
        rebrowse = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.rebrowseInterval)
                guard let self, !Task.isCancelled, self.route == .picker else { return }
                guard self.hosts.isEmpty else { continue }
                self.discovery.stop()
                self.discovery.start()
                if self.galleryReachable == false { self.probeGallery() }
            }
        }
    }

    private func stopRebrowse() {
        rebrowse?.cancel()
        rebrowse = nil
    }

    /// Coming back into the app from the Apple TV's Home screen. A remembered Host reopens straight to its
    /// art, exactly as a cold launch does (§5).
    ///
    /// It has to be handled HERE and not only in init, because init is the one place it used to live and
    /// tvOS rarely re-runs it: pressing Menu on the art stage goes to the picker and a second press exits,
    /// so the app is almost always suspended with the picker showing. Returning then resumed that same
    /// picker, and the remembered Host was never consulted — art only came back after a hard close, which
    /// is the one path that does cold-launch. An owner who left the app watching art should get art back.
    ///
    /// Only fires on a real background -> foreground transition (the caller checks), so sitting on the
    /// picker mid-session to choose a different Host is never yanked away to the old one.
    func returnedToForeground() {
        guard route == .picker else { return }                 // watching art already: nothing to restore
        guard let remembered = store.loadDefaultHost() else {
            if hosts.isEmpty { rescan() }                      // nothing remembered: just refresh the list
            return
        }
        select(remembered)
        startRememberedHostWatchdog()                          // a Host that has since gone comes back here
    }

    /// Re-kick discovery from scratch, the escape hatch the tvOS picker was missing: browsing here is
    /// started once from onAppear, so anything that left it empty (a browser that failed, a Local Network
    /// grant that landed after the browse began) had no way back short of force-quitting the app. Also
    /// serves as a manual rescan. No-op unless the picker is showing.
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
        startRebrowse()
    }

    /// Leave the art stage for the picker (the Menu/Back action, §14). Stops playback so nothing polls in
    /// the background; the picker restarts discovery when it appears.
    func showPicker() {
        connectWatchdog?.cancel()
        player.stop()
        clearManualEntry()
        route = .picker
    }

    /// Drop any half-typed address + its error. Called when a connection happens, when returning to the
    /// picker, and when the address field is abandoned, so a stale draft never lingers.
    func clearManualEntry() {
        manualAddress = ""
        manualError = nil
    }

    /// Choose a Host: remember it, stop browsing, and switch to its art.
    func select(_ host: Host) {
        store.saveDefaultHost(host)
        discovery.stop()
        stopRebrowse()
        scanFloor?.cancel()
        connectWatchdog?.cancel()
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
            let client = Self.probeClient(timeout: 3)
            let ok = (try? await client.fetchDisplay(from: .gallery)) != nil
            guard !Task.isCancelled else { return }
            self?.galleryReachable = ok
        }
    }

    /// A DisplayClient for a one-off probe: an ephemeral session with a short request timeout and no
    /// waiting for connectivity, so an address that does not answer fails in seconds rather than the
    /// shared session's sixty (E24). The Gallery probe and the manual-entry probe both use it.
    private static func probeClient(timeout: TimeInterval) -> DisplayClient {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        return DisplayClient(session: URLSession(configuration: config))
    }

    /// Connect to the public OpenObject Gallery WITHOUT remembering it (§12): unlike select(host) it saves
    /// no default Host, so the next launch returns to the picker and re-discovers the owner's real frame
    /// rather than reopening the Gallery. Offered only from the probe-gated empty-state row.
    func connectToGallery() {
        discovery.stop()
        stopRebrowse()
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
    /// rather than a silent dead end. While the probe is in flight `connecting` is true (E24) and a second
    /// submit is ignored.
    func submitManualEntry() async {
        guard !connecting else { return }
        manualError = nil
        let raw = manualAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let host = Host.manualEntry(raw) else {
            manualError = "Enter an address like 192.168.1.10 or openobject.local."
            return
        }
        connecting = true
        defer { connecting = false }
        do {
            _ = try await Self.probeClient(timeout: Self.probeTimeout).fetchDisplay(from: host)
            select(host)
        } catch {
            manualError = "No Host answered at that address."
        }
    }
}

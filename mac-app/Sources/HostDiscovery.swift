import Foundation
import Network

// Browses the local network for OpenObject Hosts — the Display/Control client side of discovery
// (MAC-APP-PLAN §B3; the counterpart to the Host advertising built in Phase A2/A3). Uses Apple's
// native NWBrowser for `_openobject._tcp`; the Node `bonjour-service` dependency is only the
// advertising side that runs inside the engine. This is the primitive that lets the Mac app (and a
// future Apple TV) find a Host — an existing XXL frame or another Mac — and offer to view/control it.
@MainActor
final class HostDiscovery: ObservableObject {
    struct Host: Identifiable, Equatable {
        let id: String          // stable Host id from the TXT record (falls back to the service name)
        let name: String        // friendly name (TXT "name", else the service instance name)
        let version: String?
        let role: String?
        let endpoint: NWEndpoint // kept so a later step can resolve it to a URL (B4)

        static func == (a: Host, b: Host) -> Bool {
            a.id == b.id && a.name == b.name && a.version == b.version && a.role == b.role
        }
    }

    @Published private(set) var hosts: [Host] = []

    private var browser: NWBrowser?

    // The raw browse list (what mDNS currently reports) is kept separate from the published `hosts`, so
    // a reachability sweep can hide Hosts that vanished UNGRACEFULLY (power-yanked or crashed) before
    // their mDNS record's TTL expires, which can take a couple of minutes. Gracefully-stopped Hosts
    // (systemd SIGTERM, or quitting the Mac app) already send an mDNS "goodbye" and drop immediately.
    private var browsed: [Host] = []
    private var strikes: [String: Int] = [:]   // consecutive failed reachability probes, per Host id
    private var probeTask: Task<Void, Never>?
    private let strikeLimit = 2                 // hide a Host after this many consecutive failures

    func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_openobject._tcp", domain: nil), using: params)
        self.browser = browser

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            // If the browser fails (e.g. permission/interface hiccup), drop it so a later start() can
            // recreate it. Discovery is additive; a failure just means no list, never a crash.
            if case .failed = state {
                Task { @MainActor in self?.stop() }
            }
        }
        browser.start(queue: .main)
        startProbing()
    }

    func stop() {
        probeTask?.cancel()
        probeTask = nil
        browser?.cancel()
        browser = nil
        browsed = []
        strikes = [:]
        hosts = []
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        var byId: [String: Host] = [:]
        for result in results {
            guard case let .service(name: serviceName, type: _, domain: _, interface: _) = result.endpoint else { continue }

            var txt: (id: String?, name: String?, version: String?, role: String?) = (nil, nil, nil, nil)
            if case let .bonjour(record) = result.metadata {
                txt = (Self.string(record, "id"), Self.string(record, "name"),
                       Self.string(record, "version"), Self.string(record, "role"))
            }

            let id = txt.id ?? serviceName
            let host = Host(id: id,
                            name: txt.name ?? serviceName,
                            version: txt.version,
                            role: txt.role,
                            endpoint: result.endpoint)
            // Dedupe by stable id: mDNS reports the same Host once per active interface (e.g. Wi-Fi
            // and Ethernet), and we want a single row.
            byId[id] = host
        }
        browsed = byId.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        // Forget strikes for Hosts mDNS no longer reports at all (they're gone regardless).
        let live = Set(browsed.map { $0.id })
        strikes = strikes.filter { live.contains($0.key) }
        publish()
    }

    // Publish the browse list minus Hosts that have failed the reachability sweep too many times.
    private func publish() {
        hosts = browsed.filter { (strikes[$0.id] ?? 0) < strikeLimit }
    }

    // Every ~10s, quietly check each browsed Host is still reachable; one that fails `strikeLimit`
    // times in a row is hidden until it answers again. This prunes power-yanked/crashed Hosts faster
    // than the mDNS TTL, without touching the browse machinery. Best-effort; a probe never throws.
    private func startProbing() {
        probeTask?.cancel()
        probeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10s
                guard let self else { return }
                await self.sweep()
            }
        }
    }

    private func sweep() async {
        for host in browsed {                    // a value copy; mid-sweep browse changes don't disturb it
            let ok = await probe(host)
            if ok { strikes[host.id] = 0 } else { strikes[host.id, default: 0] += 1 }
        }
        publish()
    }

    // A quick TCP reachability check to the Host's endpoint. Ready = reachable; a failure or a 3s
    // timeout = not. A dedicated serial queue drives both the connection and the timeout, so the two
    // can't race to resume the continuation twice.
    private func probe(_ host: Host) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let queue = DispatchQueue(label: "io.openobject.probe")
            let connection = NWConnection(to: host.endpoint, using: .tcp)
            var finished = false
            let finish: (Bool) -> Void = { ok in
                if finished { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            queue.asyncAfter(deadline: .now() + 3) { finish(false) }
            connection.start(queue: queue)
        }
    }

    private static func string(_ record: NWTXTRecord, _ key: String) -> String? {
        if case let .string(value) = record.getEntry(for: key) { return value }
        return nil
    }

    // Resolve a discovered Host's Bonjour endpoint to a reachable http URL (host:port). A browse
    // result only names the service; resolving it to an address needs a connection attempt. Used by
    // Viewer mode to open a remote Host's control panel (and, in B4, its /display). Returns nil if the
    // Host can't be reached (e.g. it just went offline).
    func resolveURL(for host: Host) async -> URL? {
        await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            let connection = NWConnection(to: host.endpoint, using: .tcp)
            var finished = false
            let finish: (URL?) -> Void = { url in
                if finished { return }
                finished = true
                connection.cancel()
                continuation.resume(returning: url)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host: nwHost, port: nwPort) = connection.currentPath?.remoteEndpoint {
                        finish(Self.httpURL(host: nwHost, port: nwPort))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .global())
        }
    }

    nonisolated private static func httpURL(host: NWEndpoint.Host, port: NWEndpoint.Port) -> URL? {
        let address: String
        switch host {
        case .ipv4(let ip): address = "\(ip)"
        case .ipv6(let ip): address = "[\(ip)]"          // IPv6 literals are bracketed in URLs
        case .name(let name, _): address = name
        @unknown default: return nil
        }
        // Trim any IPv6 zone id (e.g. "fe80::1%en0") which isn't valid in a URL host.
        let clean = address.split(separator: "%").first.map(String.init) ?? address
        return URL(string: "http://\(clean):\(port.rawValue)")
    }
}

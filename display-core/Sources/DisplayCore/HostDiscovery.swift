import Foundation
import Network
import Observation

// Bonjour discovery of OpenObject Hosts on the LAN (TVOS-APP-PLAN §5), the native counterpart to
// player/src/discovery.js's browse side. It finds `_openobject._tcp` services, reads each Host's
// identity from its TXT records (id/name/version/role — the same fields as /api/identity), resolves
// the service to a reachable host:port, and maintains a live `hosts` list for the Host picker.
//
// The Host is untouched: this only browses; it never advertises and adds no responder (so it cannot
// contend on mDNS the way a stray server would). Discovery is best-effort — if the network forbids
// multicast the list simply stays empty, and the owner falls back to manual Host entry (§5, §13).
//
// The pure part (turning a discovered service into a `Host`) is `Host.fromBonjour`, unit-tested below;
// the NWBrowser/NWConnection plumbing is integration-tested against a running Host.

@MainActor
@Observable
public final class HostDiscovery {
    /// The Hosts currently visible on the network, deduplicated by id and sorted by name. A driver /
    /// SwiftUI picker observes this.
    public private(set) var hosts: [Host] = []

    @ObservationIgnored private let serviceType: String
    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var resolved: [NWEndpoint: Host] = [:]   // endpoint -> its resolved Host
    @ObservationIgnored private var pending: Set<NWEndpoint> = []        // endpoints currently being resolved
    @ObservationIgnored private var seen: [NWEndpoint: Discovered] = [:] // last browse snapshot, keyed for retry
    @ObservationIgnored private var sweeper: Task<Void, Never>?
    // Bumped by every start/stop. In-flight resolves and restart timers carry the generation they began
    // under and drop out if it has moved on, so a previous browse session can never write into a new one.
    @ObservationIgnored private var generation = 0

    /// How long a single resolve may take before it counts as unreachable, and how often unresolved
    /// services are retried while browsing.
    private nonisolated static let resolveTimeout: TimeInterval = 3
    private nonisolated static let retryInterval: Duration = .seconds(5)

    // Network.framework delivers callbacks on the queue it is handed and documents a SERIAL queue; the
    // browser and every resolve share this one (it was .global(), a concurrent queue).
    @ObservationIgnored private nonisolated static let queue = DispatchQueue(label: "io.openobject.discovery")

    /// - Parameter serviceType: the Bonjour service, `_openobject._tcp` by default (matches
    ///   player/src/discovery.js).
    public init(serviceType: String = "_openobject._tcp") {
        self.serviceType = serviceType
    }

    /// Begin browsing. Idempotent.
    public func start() {
        guard browser == nil else { return }
        generation += 1
        let generation = self.generation
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // Extract Sendable data off the callback queue, then hop to the main actor.
            let snapshot = results.map { result in
                Discovered(endpoint: result.endpoint,
                           txt: HostDiscovery.txtDict(result.metadata),
                           serviceName: HostDiscovery.serviceName(result.endpoint))
            }
            Task { @MainActor in self?.handle(snapshot, generation: generation) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            // A failed browser used to end discovery for the whole app session (stop(), never restarted),
            // which left the picker permanently empty with no way back. Rebuild it instead.
            if case .failed = state { Task { @MainActor in self?.restart(generation: generation) } }
        }
        self.browser = browser
        browser.start(queue: HostDiscovery.queue)
        startSweeper(generation: generation)
    }

    /// Stop browsing and clear the list.
    public func stop() {
        generation += 1
        sweeper?.cancel()
        sweeper = nil
        browser?.cancel()
        browser = nil
        resolved.removeAll()
        pending.removeAll()
        seen.removeAll()
        hosts = []
    }

    // MARK: - Internals

    private struct Discovered: Sendable {
        let endpoint: NWEndpoint
        let txt: [String: String]
        let serviceName: String
    }

    private func handle(_ snapshot: [Discovered], generation: Int) {
        guard generation == self.generation else { return }
        let current = Set(snapshot.map(\.endpoint))
        // Drop Hosts whose service disappeared.
        for endpoint in Array(resolved.keys) where !current.contains(endpoint) { resolved[endpoint] = nil }
        pending.formIntersection(current)
        seen = Dictionary(snapshot.map { ($0.endpoint, $0) }, uniquingKeysWith: { _, last in last })
        rebuild()
        resolveOutstanding(generation: generation)
    }

    /// Resolve every service that is visible but not yet resolved. Called on each browse change AND on the
    /// retry sweep: a resolve that fails (or times out) leaves the endpoint unresolved, and browse results
    /// do not change again while the Host sits happily on the network, so without the sweep one bad probe
    /// hid a live Host until the app was force-quit.
    private func resolveOutstanding(generation: Int) {
        for entry in seen.values where resolved[entry.endpoint] == nil && !pending.contains(entry.endpoint) {
            pending.insert(entry.endpoint)
            Task { @MainActor [weak self] in
                let address = await HostDiscovery.resolve(entry.endpoint)
                guard let self, generation == self.generation else { return }
                self.pending.remove(entry.endpoint)
                guard let address,
                      let host = Host.fromBonjour(serviceName: entry.serviceName, txt: entry.txt,
                                                  host: address.host, port: address.port)
                else { return }   // unreachable for now; the sweeper tries again
                self.resolved[entry.endpoint] = host
                self.rebuild()
            }
        }
    }

    private func startSweeper(generation: Int) {
        sweeper?.cancel()
        sweeper = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: HostDiscovery.retryInterval)
                guard let self, !Task.isCancelled, generation == self.generation else { return }
                self.resolveOutstanding(generation: generation)
            }
        }
    }

    /// Tear the browser down and build a fresh one after a short pause (a failed browser cannot be
    /// restarted in place). Guarded by generation so it never races a stop() or a manual restart.
    private func restart(generation: Int) {
        guard generation == self.generation else { return }
        stop()
        let next = self.generation
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, next == self.generation else { return }   // stopped or restarted meanwhile
            self.start()
        }
    }

    private func rebuild() {
        var byID: [String: Host] = [:]
        for host in resolved.values { byID[host.id] = host }   // dedup (e.g. same Host on two interfaces)
        hosts = byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // TXT identity (the four keys player/src/discovery.js publishes), read straight from the browse
    // result — no resolution needed.
    private nonisolated static func txtDict(_ metadata: NWBrowser.Result.Metadata) -> [String: String] {
        guard case let .bonjour(record) = metadata else { return [:] }
        var out: [String: String] = [:]
        for key in ["id", "name", "version", "role"] {
            if case let .string(value) = record.getEntry(for: key) { out[key] = value }
        }
        return out
    }

    private nonisolated static func serviceName(_ endpoint: NWEndpoint) -> String {
        if case let .service(name, _, _, _) = endpoint { return name }
        return ""
    }

    // Resolve a Bonjour service endpoint to a reachable host:port by opening (then immediately
    // cancelling) a TCP connection and reading the resolved remote endpoint. This doubles as a
    // reachability check. Returns nil if it does not resolve within `resolveTimeout`.
    //
    // The timeout is load-bearing, not belt-and-braces. NWConnection reports a momentarily unusable path
    // as `.waiting` (NOT `.failed`) and then waits indefinitely by design, so the `default: break` below
    // used to strand the continuation forever: the endpoint stayed in `pending`, `resolveOutstanding`
    // skipped it, and a Host that was advertising perfectly well never appeared again for the life of the
    // app. `.waiting` now simply runs out the clock and reports unreachable, and the sweeper retries.
    private nonisolated static func resolve(_ endpoint: NWEndpoint) async -> (host: String, port: Int)? {
        await withCheckedContinuation { (continuation: CheckedContinuation<(host: String, port: Int)?, Never>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let once = ResumeOnce(continuation)
            let finish: (@Sendable ((host: String, port: Int)?) -> Void) = { value in
                once.resume(returning: value)
                connection.cancel()
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let remote = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = remote {
                        finish((hostString(host), Int(port.rawValue)))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break   // .waiting / .preparing: covered by the timeout below
                }
            }
            queue.asyncAfter(deadline: .now() + resolveTimeout) { finish(nil) }   // no-op once resumed
            connection.start(queue: queue)
        }
    }

    private nonisolated static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address): return address.debugDescription      // dotted quad, e.g. 192.168.1.42
        case .ipv6(let address): return "[\(address.debugDescription)]"
        case .name(let name, _): return name                          // e.g. openobject.local
        @unknown default: return ""
        }
    }
}

// Resumes a CheckedContinuation exactly once (the connection state handler can fire more than once).
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?
    init(_ continuation: CheckedContinuation<T, Never>) { self.continuation = continuation }
    func resume(returning value: T) {
        lock.lock(); defer { lock.unlock() }
        continuation?.resume(returning: value)
        continuation = nil
    }
}

public extension Host {
    /// Build a Host from a discovered `_openobject._tcp` service: its TXT identity (id/name/version,
    /// the same fields as /api/identity and player/src/discovery.js) plus the resolved host:port.
    /// Returns nil if no usable address forms. `role` is carried informally — every OpenObject instance
    /// is a Host. The default http port (80, the frame) is omitted so the baseURL reads cleanly.
    static func fromBonjour(serviceName: String, txt: [String: String], host: String, port: Int) -> Host? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        if port != 80 { components.port = port }
        guard let baseURL = components.url else { return nil }
        let nonEmpty: (String?) -> String? = { value in (value?.isEmpty == false) ? value : nil }
        let id = nonEmpty(txt["id"]) ?? baseURL.absoluteString
        let name = nonEmpty(txt["name"]) ?? (serviceName.isEmpty ? host : serviceName)
        return Host(id: id, name: name, baseURL: baseURL, version: nonEmpty(txt["version"]))
    }
}

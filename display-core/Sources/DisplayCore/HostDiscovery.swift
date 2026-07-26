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

    /// - Parameter serviceType: the Bonjour service, `_openobject._tcp` by default (matches
    ///   player/src/discovery.js).
    public init(serviceType: String = "_openobject._tcp") {
        self.serviceType = serviceType
    }

    /// Begin browsing. Idempotent.
    public func start() {
        guard browser == nil else { return }
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // Extract Sendable data off the callback queue, then hop to the main actor.
            let snapshot = results.map { result in
                Discovered(endpoint: result.endpoint,
                           txt: HostDiscovery.txtDict(result.metadata),
                           serviceName: HostDiscovery.serviceName(result.endpoint))
            }
            Task { @MainActor in self?.handle(snapshot) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed = state { Task { @MainActor in self?.stop() } }
        }
        self.browser = browser
        browser.start(queue: .global())
    }

    /// Stop browsing and clear the list.
    public func stop() {
        browser?.cancel()
        browser = nil
        resolved.removeAll()
        pending.removeAll()
        hosts = []
    }

    // MARK: - Internals

    private struct Discovered: Sendable {
        let endpoint: NWEndpoint
        let txt: [String: String]
        let serviceName: String
    }

    private func handle(_ snapshot: [Discovered]) {
        let current = Set(snapshot.map(\.endpoint))
        // Drop Hosts whose service disappeared.
        for endpoint in Array(resolved.keys) where !current.contains(endpoint) { resolved[endpoint] = nil }
        pending.formIntersection(current)
        rebuild()

        // Resolve newly-seen services to a reachable address, then add them.
        for entry in snapshot where resolved[entry.endpoint] == nil && !pending.contains(entry.endpoint) {
            pending.insert(entry.endpoint)
            Task { @MainActor [weak self] in
                let address = await HostDiscovery.resolve(entry.endpoint)
                guard let self else { return }
                self.pending.remove(entry.endpoint)
                guard let address,
                      let host = Host.fromBonjour(serviceName: entry.serviceName, txt: entry.txt,
                                                  host: address.host, port: address.port)
                else { return }
                self.resolved[entry.endpoint] = host
                self.rebuild()
            }
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
    // reachability check. Returns nil if it never resolves.
    private nonisolated static func resolve(_ endpoint: NWEndpoint) async -> (host: String, port: Int)? {
        await withCheckedContinuation { (continuation: CheckedContinuation<(host: String, port: Int)?, Never>) in
            let connection = NWConnection(to: endpoint, using: .tcp)
            let once = ResumeOnce(continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let remote = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = remote {
                        once.resume(returning: (hostString(host), Int(port.rawValue)))
                    } else {
                        once.resume(returning: nil)
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    once.resume(returning: nil)
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: .global())
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

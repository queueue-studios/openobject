import Foundation

// Persisting the owner's chosen default Host, so the app opens straight to art on later launches
// (TVOS-APP-PLAN §5). Abstracted behind a protocol so the engine and its tests never touch a real
// defaults store; the app layer supplies a UserDefaults-backed conformer in Phase C. Host is Codable,
// so any implementation is a trivial encode/decode.

public protocol HostStore: Sendable {
    /// The remembered default Host, or nil if none has been chosen.
    func loadDefaultHost() -> Host?
    /// Remember (or, with nil, forget) the default Host.
    func saveDefaultHost(_ host: Host?)
}

/// A non-persistent HostStore for tests and previews.
public final class InMemoryHostStore: HostStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Host?

    public init(_ initial: Host? = nil) { stored = initial }

    public func loadDefaultHost() -> Host? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func saveDefaultHost(_ host: Host?) {
        lock.lock(); defer { lock.unlock() }
        stored = host
    }
}

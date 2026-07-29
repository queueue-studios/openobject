import Foundation

// The app-side HostStore: persists the owner's chosen Host in UserDefaults so an app opens straight to
// its art on later launches (TVOS-APP-PLAN §5). It lives HERE in DisplayCore (not in an app target) so
// the tvOS and iPad apps share one implementation; it is Foundation-only, so it also builds on the
// macOS test platform, unlike the SwiftUI/UIKit views in DisplayUI. DisplayCore also ships the in-memory
// HostStore for tests and previews. Stored as JSON under one key; a decode failure is treated as
// "nothing remembered".
public struct UserDefaultsHostStore: HostStore {
    private let key = "openobject.defaultHost"

    public init() {}

    public func loadDefaultHost() -> Host? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Host.self, from: data)
    }

    public func saveDefaultHost(_ host: Host?) {
        guard let host, let data = try? JSONEncoder().encode(host) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

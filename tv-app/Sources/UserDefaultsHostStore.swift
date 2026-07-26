import Foundation
import DisplayCore

// Persists the owner's chosen Host in UserDefaults so the app opens straight to its art on later launches
// (TVOS-APP-PLAN §5). This is the app-side HostStore; display-core ships only the in-memory one (for
// tests/previews). Stored as JSON under one key; a decode failure is treated as "nothing remembered".
struct UserDefaultsHostStore: HostStore {
    private let key = "openobject.defaultHost"

    func loadDefaultHost() -> Host? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Host.self, from: data)
    }

    func saveDefaultHost(_ host: Host?) {
        guard let host, let data = try? JSONEncoder().encode(host) else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(data, forKey: key)
    }
}

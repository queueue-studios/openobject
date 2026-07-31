import Foundation

// A Host is an OpenObject server on the network (player/server.js) that this Display renders. The app
// finds Hosts by Bonjour (discovery) or the owner types one in (manual entry, TVOS-APP-PLAN §5);
// either way a Host boils down to a name to show in the picker and a base URL to fetch from. Every
// path this Display reads (/api/display, /uploads/…, /folder-media/…) resolves against `baseURL`,
// exactly as a browser display's same-origin fetches resolve against its page's origin — so "which
// Host" is simply which baseURL we point at (§3). The Host itself is unchanged and Host-neutral (§11).

public struct Host: Sendable, Hashable, Codable, Identifiable {
    /// Stable identity. For a discovered Host this is the Bonjour / `/api/identity` id; for a
    /// manually-entered one it defaults to the origin string until `/api/identity` is read (B3).
    public var id: String
    /// Friendly name for the Host picker. Defaults to the typed host for manual entry.
    public var name: String
    /// Origin only (scheme + host + optional port), e.g. `http://openobject.local` or
    /// `http://192.168.1.42:3000`. Every fetch is resolved against this.
    public var baseURL: URL
    /// The Host's player version if known (Bonjour TXT / `/api/identity`), else nil.
    public var version: String?

    public init(id: String, name: String, baseURL: URL, version: String? = nil) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.version = version
    }
}

public extension Host {
    /// Build a Host from an address the owner typed (manual entry, §5; also the App Store review path,
    /// §12). Accepts a bare host (`openobject.local`, `192.168.1.42`), a `host:port`
    /// (`192.168.1.42:3000`), or a full URL (`http://192.168.1.42:3000`). A bare host implies plain
    /// http on the standard port, which is exactly how the frame serves (the installer sets PORT=80, so
    /// `http://openobject.local` is correct); a Mac dev Host on :3000 is normally discovered, or its
    /// port is typed. Any path/query is dropped to the origin. Returns nil if no usable host parses.
    static func manualEntry(_ raw: String) -> Host? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Add a scheme when the owner omitted one, so URLComponents can find the authority (without it,
        // "192.168.1.42:3000" would misparse the address as a scheme).
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let comps = URLComponents(string: withScheme),
              let host = comps.host, !host.isEmpty else { return nil }
        // Only http/https make sense for a Host; anything odd falls back to http.
        var origin = URLComponents()
        origin.scheme = (comps.scheme?.lowercased() == "https") ? "https" : "http"
        origin.host = host
        origin.port = comps.port
        guard let baseURL = origin.url else { return nil }
        return Host(id: baseURL.absoluteString, name: host, baseURL: baseURL, version: nil)
    }
}

public extension Host {
    /// The public OpenObject Gallery: a hosted demo Host the picker offers in its empty state (no Host
    /// found on the network) so a new owner (or an App Store reviewer) sees real art immediately without
    /// running a Host of their own (§12/§13). It is an ordinary Host (this app is a dumb client of its
    /// /api/display); the art lives on that public origin, never in the app or repo (§3). Choosing it is
    /// NON-persisting (AppModel.connectToGallery), so the next launch still discovers the owner's real
    /// frame. The picker only shows it when a live probe of this origin answers, so it is never a dead
    /// button. HTTPS, so it needs no ATS exception (unlike LAN Hosts).
    static let gallery = Host(
        id: "openobject-gallery",
        name: "OpenObject Gallery",
        baseURL: URL(string: "https://gallery.openobject.io")!
    )
}

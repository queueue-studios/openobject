import Foundation

// A Connected piece's bundle URL, built exactly as player/public/display.js builds the iframe `src` for
// the frame and the Mac (HANDOFF §17 "Connected Collections on the viewer apps"). The iOS app points a
// web view at this URL on the Host's own same-origin mirror, so the piece renders from the same files with
// the same seed and the same controls as every other display. Nothing here is new to the Host.
//
// The contract, in the order display.js emits it:
//   /collections/<collection>[/<token>]/index.html
//     ?<seed query from source_url>          a shared bundle's per-piece seed (spliced raw)
//     &_pix:<n>                              a GPU-heavy bundle's density, on phones (and the frame)
//     &rpc_url=<enc>                         a live-RPC collection's node
//     &ooanim=1                              the animate hook
//     &oospeed=<n>                           a speedControl collection's 0..10 speed
//     &oochoice=<v>                          a single-choice control's value
//     &oo_<key>=<v>…                         the general controls, audio ones forced silent when muted
//     #<fragment from source_url>            a hash-seeded shared bundle's seed (inkField), kept last
// The query seed and the fragment are split first so the query never swallows the hash, as in display.js.
// Control keys are emitted in sorted order (display.js walks the Host's object in insertion order; no
// bundle depends on the order, and sorting keeps the URL deterministic).
public enum ConnectedURL {
    /// Audio controls and the value that means "silent" (display.js AUDIO_CONTROLS). The display's Sound
    /// setting is a master gate above a collection's own audio control (§12): muted forces these.
    public static let audioControls: [String: String] = ["music": "off"]

    /// The piece's controls with the audio ones forced to their silent value when `muted` (display.js
    /// gatedControls). Nil when the piece has no controls.
    public static func gatedControls(for item: DisplayItem, muted: Bool) -> [String: String]? {
        guard muted, var out = item.controls else { return item.controls }
        for (key, silent) in audioControls where out[key] != nil { out[key] = silent }
        return out
    }

    /// The host-relative page path with its query and fragment, or nil for a piece that is not Connected
    /// (or lacks its collection). `phone` is display.js's isPhone(): a phone gets the bundle's frame pixel
    /// density (Matt, 2026-09-15); an iPad keeps the bundle's own default, like the Mac.
    public static func path(for item: DisplayItem, phone: Bool, muted: Bool) -> String? {
        guard item.kind == .connected, let collection = item.collection else { return nil }
        var params: [String] = []
        let src = item.sourceURL ?? ""
        let fragment: String
        let beforeFragment: String
        if let hash = src.firstIndex(of: "#") {
            fragment = String(src[hash...])
            beforeFragment = String(src[..<hash])
        } else {
            fragment = ""
            beforeFragment = src
        }
        if let q = beforeFragment.firstIndex(of: "?") {
            params.append(String(beforeFragment[beforeFragment.index(after: q)...]))   // the per-piece seed
        }
        if phone, let density = item.framePixelDensity {
            params.append("_pix:" + JSScalar.jsNumber(density))
        }
        if let rpc = item.rpcUrl { params.append("rpc_url=" + encode(rpc)) }
        if item.animate { params.append("ooanim=1") }
        if let speed = item.speed { params.append("oospeed=" + encode(JSScalar.jsNumber(speed))) }
        if let choice = item.choice { params.append("oochoice=" + encode(choice)) }
        if let controls = gatedControls(for: item, muted: muted) {
            for key in controls.keys.sorted() { params.append("oo_" + key + "=" + encode(controls[key]!)) }
        }
        var tokenSegment = ""
        if item.perToken, let token = item.tokenId { tokenSegment = "/" + encode(token) }
        let query = params.isEmpty ? "" : "?" + params.joined(separator: "&")
        return "/collections/" + collection + tokenSegment + "/index.html" + query + fragment
    }

    /// The absolute URL on a Host: `path` resolved against the Host's baseURL.
    public static func url(for item: DisplayItem, on host: Host, phone: Bool, muted: Bool) -> URL? {
        guard let path = path(for: item, phone: phone, muted: muted) else { return nil }
        return URL(string: path, relativeTo: host.baseURL)?.absoluteURL
    }

    /// Everything of the piece that reaches its URL or its layout, joined for the engine's restyle
    /// signature: a control-panel change to any of it while the piece is on screen reloads the piece in
    /// place (display.js's connected `sig`). Independent of the device and of the Sound setting, which the
    /// iOS app cannot change while the stage is up.
    public static func signature(for item: DisplayItem) -> String {
        let controls = (item.controls ?? [:]).keys.sorted().map { "\($0)=\(item.controls![$0]!)" }.joined(separator: ",")
        return [
            item.collection ?? "", item.tokenId ?? "", item.sourceURL ?? "", item.perToken ? "1" : "0",
            item.animate ? "1" : "0", item.speed.map(JSScalar.jsNumber) ?? "", item.choice ?? "",
            item.rpcUrl ?? "", controls, item.crop.map(JSScalar.jsNumber) ?? "", item.aspect ?? "",
        ].joined(separator: "|")
    }

    /// JavaScript's encodeURIComponent: everything but A-Z a-z 0-9 - _ . ! ~ * ' ( ) is percent-encoded.
    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: uriComponentAllowed) ?? s
    }

    private static let uriComponentAllowed: CharacterSet = {
        var ascii = CharacterSet()   // ASCII only: CharacterSet.alphanumerics would admit non-ASCII letters
        for scalar in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()".unicodeScalars {
            ascii.insert(scalar)
        }
        return ascii
    }()
}

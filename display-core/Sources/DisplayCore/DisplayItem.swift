import Foundation

// One piece in a Host's rotation, as it arrives on /api/display. The Host sends three shapes that this
// one model absorbs (all verified against captured fixtures):
//   • Library upload: id is an Int, no `src` (the display builds /uploads/<filename>).
//   • Connected piece: id is an Int; kind and format are both "connected", plus the render fields below.
//   • Folder item: id is a String ("fc<folderId>:<filename>") with a host-relative `src`.
// Only the fields a Display needs are decoded; everything else the Host sends (original_name, mime,
// bytes, thumb, …) is ignored, and unknown/new fields never break decoding, so the app works against any
// Host version (§11). id is normalized to String because the engine uses it only as an opaque identity,
// to keep tracking a piece across polls, exactly as display.js does.
//
// The Connected render fields (collection, token, seed, controls, crop, aspect, …) are what display.js
// turns into the piece's iframe URL (HANDOFF §17 "Connected Collections on the viewer apps"). They were
// added 2026-09-16 for the iOS app's web view; tvOS decodes them too but never renders a Connected piece
// (CapabilityFilter). They are also written into the iPad's local-copy manifest, so phase two (offline
// Connected art) reads them back without a migration.

/// Fit vs Fill for a piece (HANDOFF §6). Defaults to Fit.
public enum Fit: String, Sendable, Codable {
    case fit
    case fill
}

public struct DisplayItem: Sendable, Hashable, Identifiable, Codable {
    public let id: String
    public let kind: MediaKind?
    public let format: MediaFormat?
    public let fit: Fit
    /// Present for Library and Folder items; used to build /uploads/<filename> when `src` is absent.
    public let filename: String?
    /// Folder items only: a host-relative media URL (/folder-media/…). Preferred over `filename` when
    /// set, matching display.js (`item.src || '/uploads/' + item.filename`).
    public let src: String?

    // MARK: Connected pieces only (all nil / false otherwise). Names follow the wire fields.

    /// The collection slug: the bundle lives at /collections/<collection>[/<token>]/index.html.
    public let collection: String?
    /// The token id (a String on the wire, or a number from an older Host).
    public let tokenId: String?
    /// The official URL of the piece. A shared bundle carries its per-piece seed here, as a `?query`
    /// and/or a `#fragment`, which the display re-applies to the local bundle URL.
    public let sourceURL: String?
    /// A per-token bundle directory (Art Blocks style) rather than one shared bundle.
    public let perToken: Bool
    /// Fire the bundle's animate hook (`?ooanim=1`).
    public let animate: Bool
    /// A speedControl collection's 0..10 motion speed (`?oospeed=`).
    public let speed: Double?
    /// A single-choice control's selected value (`?oochoice=`).
    public let choice: String?
    /// The general controls, key to value (`?oo_<key>=`). Values are strings on the wire or numbers;
    /// numbers are kept in their JavaScript spelling (2.5 stays "2.5", 2 stays "2").
    public let controls: [String: String]?
    /// A live-RPC collection's node (`?rpc_url=`).
    public let rpcUrl: String?
    /// The centered fraction of the bundle the art occupies; the display zooms it edge to edge (§6).
    public let crop: Double?
    /// A declared aspect ratio, CSS spelling ("1920 / 1080"); the display letterboxes it (§6).
    public let aspect: String?
    /// A GPU-heavy bundle's pixel density for a frame Display, and for phones (`?_pix:<n>`, display.js).
    public let framePixelDensity: Double?
    /// sessionStorage keys the display sets right before the bundle loads (inkField's force-live).
    public let sessionFlags: [String: String]?
    /// Reveal on the bundle's first painted frame rather than its load event (display.js waitForPaint).
    public let awaitPaint: Bool

    public init(id: String, kind: MediaKind?, format: MediaFormat?, fit: Fit = .fit,
                filename: String? = nil, src: String? = nil,
                collection: String? = nil, tokenId: String? = nil, sourceURL: String? = nil,
                perToken: Bool = false, animate: Bool = false, speed: Double? = nil, choice: String? = nil,
                controls: [String: String]? = nil, rpcUrl: String? = nil, crop: Double? = nil,
                aspect: String? = nil, framePixelDensity: Double? = nil,
                sessionFlags: [String: String]? = nil, awaitPaint: Bool = false) {
        self.id = id
        self.kind = kind
        self.format = format
        self.fit = fit
        self.filename = filename
        self.src = src
        self.collection = collection
        self.tokenId = tokenId
        self.sourceURL = sourceURL
        self.perToken = perToken
        self.animate = animate
        self.speed = speed
        self.choice = choice
        self.controls = controls
        self.rpcUrl = rpcUrl
        self.crop = crop
        self.aspect = aspect
        self.framePixelDensity = framePixelDensity
        self.sessionFlags = sessionFlags
        self.awaitPaint = awaitPaint
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, format, fit, filename, src
        case collection
        case tokenId = "token_id"
        case sourceURL = "source_url"
        case perToken, animate, speed, choice, controls, rpcUrl, crop, aspect, framePixelDensity
        case sessionFlags, awaitPaint
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id is required and polymorphic: an Int for Library/Connected, a String for Folder.
        if let intID = try? c.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        // Lenient reads: a wrong-typed, null, or unknown value becomes nil / false rather than throwing (§11).
        func optString(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        func optScalar(_ key: CodingKeys) -> String? {
            ((try? c.decodeIfPresent(JSScalar.self, forKey: key)) ?? nil)?.text
        }
        func optDouble(_ key: CodingKeys) -> Double? {
            (try? c.decodeIfPresent(Double.self, forKey: key)) ?? nil
        }
        func flag(_ key: CodingKeys) -> Bool {
            ((try? c.decodeIfPresent(Bool.self, forKey: key)) ?? nil) ?? false
        }
        kind = optString(.kind).flatMap(MediaKind.init(rawValue:))
        format = optString(.format).flatMap(MediaFormat.init(rawValue:))
        filename = optString(.filename)
        src = optString(.src)
        let decodedFit: Fit? = (try? c.decodeIfPresent(Fit.self, forKey: .fit)) ?? nil
        fit = decodedFit ?? .fit // absent/odd -> Fit, matching display.js

        collection = optString(.collection)
        tokenId = optScalar(.tokenId)
        sourceURL = optString(.sourceURL)
        perToken = flag(.perToken)
        animate = flag(.animate)
        speed = optDouble(.speed)
        choice = optScalar(.choice)
        controls = ((try? c.decodeIfPresent([String: JSScalar].self, forKey: .controls)) ?? nil)?
            .mapValues(\.text)
        rpcUrl = optString(.rpcUrl)
        crop = optDouble(.crop)
        aspect = optString(.aspect)
        framePixelDensity = optDouble(.framePixelDensity)
        sessionFlags = ((try? c.decodeIfPresent([String: JSScalar].self, forKey: .sessionFlags)) ?? nil)?
            .mapValues(\.text)
        awaitPaint = flag(.awaitPaint)
    }

    // Encoding exists for one reason: the iPad's local copy persists the last /api/display response as its
    // manifest (HANDOFF §17), and it must read back through the same lenient decoder above. Only the decoded
    // fields are written (id already normalized to a String, which the decoder accepts).
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(kind, forKey: .kind)
        try c.encodeIfPresent(format, forKey: .format)
        try c.encode(fit, forKey: .fit)
        try c.encodeIfPresent(filename, forKey: .filename)
        try c.encodeIfPresent(src, forKey: .src)
        try c.encodeIfPresent(collection, forKey: .collection)
        try c.encodeIfPresent(tokenId, forKey: .tokenId)
        try c.encodeIfPresent(sourceURL, forKey: .sourceURL)
        if perToken { try c.encode(true, forKey: .perToken) }
        if animate { try c.encode(true, forKey: .animate) }
        try c.encodeIfPresent(speed, forKey: .speed)
        try c.encodeIfPresent(choice, forKey: .choice)
        try c.encodeIfPresent(controls, forKey: .controls)
        try c.encodeIfPresent(rpcUrl, forKey: .rpcUrl)
        try c.encodeIfPresent(crop, forKey: .crop)
        try c.encodeIfPresent(aspect, forKey: .aspect)
        try c.encodeIfPresent(framePixelDensity, forKey: .framePixelDensity)
        try c.encodeIfPresent(sessionFlags, forKey: .sessionFlags)
        if awaitPaint { try c.encode(true, forKey: .awaitPaint) }
    }
}

public extension DisplayItem {
    /// Whether this native Display can render this piece. Connected pieces render only where the filter
    /// says so (the iOS app's web view); SVG/WebM are skipped; an unknown kind falls back to a format
    /// decision (CapabilityFilter, §6, §11).
    func isRenderable(using filter: CapabilityFilter = CapabilityFilter()) -> Bool {
        filter.canRender(kind: kind, format: format)
    }
}

/// A JSON scalar read the way JavaScript would stringify it: a string as is, a whole number without a
/// decimal point, any other number in its shortest form, a boolean as "true"/"false". Used for the wire
/// fields (`token_id`, `choice`, control values) a Host may send as either strings or numbers, so the URL
/// the iOS web view builds matches display.js's byte for byte.
struct JSScalar: Decodable, Sendable {
    let text: String

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { text = s; return }
        if let b = try? c.decode(Bool.self) { text = b ? "true" : "false"; return }
        if let i = try? c.decode(Int.self) { text = String(i); return }
        let d = try c.decode(Double.self)
        text = JSScalar.jsNumber(d)
    }

    /// A Double in JavaScript's default `String(n)` spelling for the values this app meets: integral
    /// values print without ".0", the rest in Swift's shortest round-trip form (which matches JS for
    /// ordinary decimals such as 2.5 or 0.75).
    static func jsNumber(_ d: Double) -> String {
        if d.isFinite, d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }
}

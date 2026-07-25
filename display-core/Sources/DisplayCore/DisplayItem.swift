import Foundation

// One piece in a Host's rotation, as it arrives on /api/display. The Host sends three shapes that this
// one model absorbs (all verified against captured fixtures):
//   • Library upload  — id is an Int, no `src` (the display builds /uploads/<filename>).
//   • Connected piece — id is an Int; kind and format are both "connected" (skipped natively, §2).
//   • Folder item     — id is a String ("fc<folderId>:<filename>") with a host-relative `src`.
// Only the fields this native Display needs are decoded; everything else the Host sends (original_name,
// mime, bytes, connected render params, …) is ignored, and unknown/new fields never break decoding, so
// the app works against any Host version (§11). id is normalized to String because the engine uses it
// only as an opaque identity — to keep tracking a piece across polls — exactly as display.js does.

/// Fit vs Fill for a piece (HANDOFF §6). Defaults to Fit.
public enum Fit: String, Sendable, Codable {
    case fit
    case fill
}

public struct DisplayItem: Sendable, Hashable, Identifiable, Decodable {
    public let id: String
    public let kind: MediaKind?
    public let format: MediaFormat?
    public let fit: Fit
    /// Present for Library and Folder items; used to build /uploads/<filename> when `src` is absent.
    public let filename: String?
    /// Folder items only: a host-relative media URL (/folder-media/…). Preferred over `filename` when
    /// set, matching display.js (`item.src || '/uploads/' + item.filename`).
    public let src: String?

    public init(id: String, kind: MediaKind?, format: MediaFormat?, fit: Fit = .fit,
                filename: String? = nil, src: String? = nil) {
        self.id = id
        self.kind = kind
        self.format = format
        self.fit = fit
        self.filename = filename
        self.src = src
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, format, fit, filename, src
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // id is required and polymorphic: an Int for Library/Connected, a String for Folder.
        if let intID = try? c.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        // Lenient string reads: a wrong-typed or unknown value becomes nil rather than throwing (§11).
        func optString(_ key: CodingKeys) -> String? {
            (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil
        }
        kind = optString(.kind).flatMap(MediaKind.init(rawValue:))
        format = optString(.format).flatMap(MediaFormat.init(rawValue:))
        filename = optString(.filename)
        src = optString(.src)
        let decodedFit: Fit? = (try? c.decodeIfPresent(Fit.self, forKey: .fit)) ?? nil
        fit = decodedFit ?? .fit // absent/odd -> Fit, matching display.js
    }
}

public extension DisplayItem {
    /// Whether this native Display can render this piece. Connected pieces and SVG/WebM are skipped; an
    /// unknown kind falls back to a format decision (CapabilityFilter, §6, §11).
    func isRenderable(using filter: CapabilityFilter = CapabilityFilter()) -> Bool {
        filter.canRender(kind: kind, format: format)
    }
}

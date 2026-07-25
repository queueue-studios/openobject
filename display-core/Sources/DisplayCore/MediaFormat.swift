// The nine upload formats OpenObject supports and the four render "kinds" they map to, mirroring
// player/src/formats.js exactly (the Host's authoritative table). Raw values match the strings the
// Host puts on each /api/display item (`format`, `kind`), so decoding is a plain rawValue lookup.
// This is the FULL supported set, not the tvOS-renderable subset — CapabilityFilter decides which of
// these this native Display can actually render (TVOS-APP-PLAN §6).

/// How a piece is rendered. Uploaded files are `still` / `animated` / `video`; a Connected Collection
/// is a web program (`connected`) with no native renderer on tvOS (TVOS-APP-PLAN §2).
public enum MediaKind: String, Sendable, Codable, CaseIterable {
    case still
    case animated
    case video
    case connected
}

/// A supported upload format. Raw values are the Host's `format` strings (note `jpeg`, not `jpg`).
public enum MediaFormat: String, Sendable, Codable, CaseIterable {
    case jpeg
    case png
    case gif
    case avif
    case webp
    case svg
    case mp4
    case mov
    case webm

    /// The render kind this format maps to, matching player/src/formats.js. (The Host also sends `kind`
    /// on each item; this mapping lets the engine validate or derive it from the format alone.)
    public var kind: MediaKind {
        switch self {
        case .jpeg, .png: return .still
        case .gif, .avif, .webp, .svg: return .animated
        case .mp4, .mov, .webm: return .video
        }
    }
}

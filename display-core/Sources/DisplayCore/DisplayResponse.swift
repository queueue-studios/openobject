// The whole /api/display payload for one poll (verified against captured fixtures). Only the fields
// this native Display acts on are decoded: items, durationMs, mode, pinnedId, asleep, source.
//
// Deliberately NOT decoded: `muted` (that is the WEB display's mute; a tvOS/iPad app owns its OWN audio
// setting, §10) and `retroArcade` (the easter egg is out of tvOS v1, §5). Unknown fields are ignored,
// so a Host older than this app (no `muted`) or newer (extra fields) decodes fine (§11).

public enum RotationMode: String, Sendable, Codable {
    case sequence
    case shuffle
}

public enum Source: String, Sendable, Codable {
    case library
    case folder
}

public struct DisplayResponse: Sendable, Decodable {
    public let items: [DisplayItem]
    public let durationMs: Int
    public let mode: RotationMode
    /// The pinned Library id if a piece is pinned, else nil. Normalized to String to match
    /// DisplayItem.id. (The Host also collapses `items` to just the pinned piece, §8.)
    public let pinnedId: String?
    public let asleep: Bool
    public let source: Source

    public init(items: [DisplayItem], durationMs: Int = 8000, mode: RotationMode = .sequence,
                pinnedId: String? = nil, asleep: Bool = false, source: Source = .library) {
        self.items = items
        self.durationMs = durationMs
        self.mode = mode
        self.pinnedId = pinnedId
        self.asleep = asleep
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case items, durationMs, mode, pinnedId, asleep, source
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([DisplayItem].self, forKey: .items)
        durationMs = (try? c.decode(Int.self, forKey: .durationMs)) ?? 8000
        let modeRaw = (try? c.decodeIfPresent(String.self, forKey: .mode)) ?? nil
        mode = modeRaw.flatMap(RotationMode.init(rawValue:)) ?? .sequence
        // pinnedId is an Int Library id, or null/absent.
        if let intPin = try? c.decode(Int.self, forKey: .pinnedId) {
            pinnedId = String(intPin)
        } else {
            pinnedId = (try? c.decodeIfPresent(String.self, forKey: .pinnedId)) ?? nil
        }
        asleep = (try? c.decode(Bool.self, forKey: .asleep)) ?? false
        let sourceRaw = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
        source = sourceRaw.flatMap(Source.init(rawValue:)) ?? .library
    }
}

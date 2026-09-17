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

/// The two rotation settings an iPad may change while playing its local copy (HANDOFF §17, E26): the
/// duration and the order. Nil fields mean "the Host's captured value". Held with the local copy, applied
/// only while the Host is not answering, cleared on the next successful poll.
public struct RotationOverride: Sendable, Codable, Equatable {
    public var durationMs: Int?
    public var mode: RotationMode?
    public init(durationMs: Int? = nil, mode: RotationMode? = nil) {
        self.durationMs = durationMs
        self.mode = mode
    }
    public var isEmpty: Bool { durationMs == nil && mode == nil }
}

public struct DisplayResponse: Sendable, Codable, Equatable {
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

    // Encoding exists for the iPad's local-copy manifest (HANDOFF §17): the last successful response is
    // written to disk and read back through the lenient decoder above on an offline launch.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(items, forKey: .items)
        try c.encode(durationMs, forKey: .durationMs)
        try c.encode(mode, forKey: .mode)
        try c.encodeIfPresent(pinnedId, forKey: .pinnedId)
        try c.encode(asleep, forKey: .asleep)
        try c.encode(source, forKey: .source)
    }

    /// The same response with an offline override's duration and/or mode in place of the Host's (§17, E26).
    public func overridden(by override: RotationOverride?) -> DisplayResponse {
        guard let override else { return self }
        return DisplayResponse(items: items, durationMs: override.durationMs ?? durationMs,
                               mode: override.mode ?? mode, pinnedId: pinnedId, asleep: asleep, source: source)
    }

    /// The same response without its Connected pieces. A web view can only load a Connected piece from a
    /// Host that answers, so when the Host stops answering the iOS player plays on without them (HANDOFF
    /// §17, phase one); the next successful poll brings them back. A Pin on a Connected piece is dropped
    /// with it rather than collapsing the rotation to nothing.
    public var withoutConnected: DisplayResponse { droppingConnected(unless: { _ in false }) }

    /// The same response without the Connected pieces `keep` rejects: offline, the ones whose bundle the local
    /// copy does not hold (§17 phase two). A Pin on a dropped piece goes with it.
    public func droppingConnected(unless keep: (DisplayItem) -> Bool) -> DisplayResponse {
        let kept = items.filter { $0.kind != .connected || keep($0) }
        let pin = kept.contains { $0.id == pinnedId } ? pinnedId : nil
        return DisplayResponse(items: kept, durationMs: durationMs, mode: mode, pinnedId: pin,
                               asleep: asleep, source: source)
    }

    /// Whether any piece is a Connected one.
    public var hasConnected: Bool { items.contains { $0.kind == .connected } }

    /// The same response with Sleep cleared. The iPad's local copy plays through the Host's sleep hours when
    /// the Host is not there to say otherwise (offline ignores the schedule, §17), so a saved or last-seen
    /// response is applied awake.
    public var awake: DisplayResponse {
        DisplayResponse(items: items, durationMs: durationMs, mode: mode, pinnedId: pinnedId,
                        asleep: false, source: source)
    }
}

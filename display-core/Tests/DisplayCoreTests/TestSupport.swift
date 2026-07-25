import Foundation
@testable import DisplayCore

// Shared test helpers.

/// A deterministic RandomNumberGenerator (SplitMix64) so Shuffle passes are reproducible in tests.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// A renderable test item (still/JPEG by default). Pass a connected/SVG/WebM kind+format to make a
/// piece the CapabilityFilter should skip.
func item(_ id: String, _ kind: MediaKind = .still, _ format: MediaFormat = .jpeg, fit: Fit = .fit) -> DisplayItem {
    DisplayItem(id: id, kind: kind, format: format, fit: fit, filename: "\(id).jpg", src: nil)
}

func libraryResponse(_ items: [DisplayItem], mode: RotationMode = .sequence, pinnedId: String? = nil,
                     asleep: Bool = false, durationMs: Int = 8000) -> DisplayResponse {
    DisplayResponse(items: items, durationMs: durationMs, mode: mode, pinnedId: pinnedId,
                    asleep: asleep, source: .library)
}

enum FixtureError: Error { case missing(String) }

/// Decode a captured /api/display fixture from the test bundle.
func loadDisplayFixture(_ name: String) throws -> DisplayResponse {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
        throw FixtureError.missing(name)
    }
    return try JSONDecoder().decode(DisplayResponse.self, from: Data(contentsOf: url))
}

/// The id of the piece the engine currently has on screen, or nil if idle/sleeping.
func playingID(_ engine: RotationEngine) -> String? {
    if case let .playing(item) = engine.screen { return item.id }
    return nil
}

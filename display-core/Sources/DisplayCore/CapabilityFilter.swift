// What THIS native Display can render. The tvOS app renders everything the web player supports EXCEPT
// SVG and WebM (declined with reasons, TVOS-APP-PLAN §6) and Connected Collections (skipped, §2).
//
// The filter lives in the app, never the Host: it decides from what it can DECODE, never from a flag
// the Host might not send, so it works against any Host version, older or newer (§11). A skipped piece
// is passed over exactly as the web display skips an unsupported upload — no error; the rotation just
// plays its renderable pieces, and if nothing is renderable the app shows the idle splash (§4, §8).

public struct CapabilityFilter: Sendable {
    /// Formats this Display can decode natively. Everything except SVG (would be static-only on tvOS,
    /// breaking the project's "never freeze on frame one" rule, §6) and WebM (its decoders are LGPL, a
    /// legal question inside a proprietary App Store binary, §6). Animated AVIF stays in pending a
    /// Phase C check that ImageIO decodes AVIS sequences (§6, §16); still AVIF is fine since tvOS 16.
    public static let renderableFormats: Set<MediaFormat> = [.jpeg, .png, .gif, .avif, .webp, .mp4, .mov]

    public init() {}

    /// Whether this Display can render a piece with the given kind and format. A Connected piece is
    /// never renderable (it is a web program with no native engine, §2); otherwise it comes down to
    /// whether the format decodes here. An absent/unknown format is treated as not renderable (safe).
    public func canRender(kind: MediaKind, format: MediaFormat?) -> Bool {
        if kind == .connected { return false }
        guard let format else { return false }
        return Self.renderableFormats.contains(format)
    }
}

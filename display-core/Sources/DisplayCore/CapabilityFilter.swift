// What THIS native Display can render. The tvOS app renders everything the web player supports EXCEPT
// SVG and WebM (declined with reasons, TVOS-APP-PLAN §6) and Connected Collections (skipped, §2). The
// iOS app opts in to Connected pieces, which it renders in a web view (HANDOFF §17, 2026-09-16).
//
// The filter lives in the app, never the Host: it decides from what it can DECODE, never from a flag
// the Host might not send, so it works against any Host version, older or newer (§11). A skipped piece
// is passed over exactly as the web display skips an unsupported upload — no error; the rotation just
// plays its renderable pieces, and if nothing is renderable the app shows the idle splash (§4, §8).

public struct CapabilityFilter: Sendable {
    /// Formats this Display can decode natively. Everything except SVG (would be static-only on tvOS,
    /// breaking the project's "never freeze on frame one" rule, §6) and WebM (its decoders are LGPL, a
    /// legal question inside a proprietary App Store binary, §6). Animated AVIF (AVIS) is confirmed
    /// (Phase C, §6/§16): ImageIO reports the frame sequence and per-frame delays, so it animates like
    /// GIF/WebP; on an OS whose ImageIO lacks AVIS decode it simply shows the first frame, never errors.
    public static let renderableFormats: Set<MediaFormat> = [.jpeg, .png, .gif, .avif, .webp, .mp4, .mov]

    /// Whether Connected pieces count as renderable. Off by default (tvOS, the local copy's wanted set);
    /// the iOS app's live player turns it on, since it has a web view to run them in.
    public let rendersConnected: Bool

    public init(rendersConnected: Bool = false) {
        self.rendersConnected = rendersConnected
    }

    /// Whether this Display can render a piece with the given kind and format. A Connected piece renders
    /// only where `rendersConnected` says so (it is a web program; only a web view can run it, §2);
    /// otherwise it comes down to whether the format decodes here. An absent/unknown format, or an
    /// unrecognized kind from a newer Host, is treated conservatively: unknown formats are not
    /// renderable, and a nil kind decides by format alone (so a future non-connected kind still plays if
    /// we can decode it, §11).
    public func canRender(kind: MediaKind?, format: MediaFormat?) -> Bool {
        if kind == .connected { return rendersConnected }
        guard let format else { return false }
        return Self.renderableFormats.contains(format)
    }
}

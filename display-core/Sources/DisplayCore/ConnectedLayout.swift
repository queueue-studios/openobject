import Foundation

// How a Connected piece's web view is sized on a stage, ported from player/public/display.css (HANDOFF
// §6): a declared `aspect` is contained inside the stage (Fit) or covers it (Fill), centered, so the bare
// black stage forms the letterbox; a `crop` oversizes the layer by one over the fraction the art occupies
// so it reaches the edges, with the overflow clipped. Oversizing rather than scaling keeps the generator
// rendering at full resolution, so pixel art stays crisp. Pure geometry, so it unit-tests on the Mac.
public enum ConnectedLayout {
    /// The box the web view should be given, centered on a stage of `stage` points. Larger than the stage
    /// when the piece crops or fills; the caller clips to the stage.
    public static func box(for item: DisplayItem, in stage: CGSize) -> CGSize {
        var box = stage
        if let ratio = item.aspect.flatMap(ratio(from:)), ratio > 0, stage.width > 0, stage.height > 0 {
            if item.fit == .fill {
                box = CGSize(width: max(stage.width, stage.height * ratio), height: max(stage.height, stage.width / ratio))
            } else {
                box = CGSize(width: min(stage.width, stage.height * ratio), height: min(stage.height, stage.width / ratio))
            }
        }
        if let crop = item.crop, crop > 0, crop < 1 {
            box = CGSize(width: box.width / crop, height: box.height / crop)
        }
        return box
    }

    /// A CSS aspect-ratio value as the registry spells it ("1920 / 1080", "1 / 1", "16/9", or a bare
    /// number) as width over height, or nil if unreadable.
    public static func ratio(from aspect: String) -> Double? {
        let parts = aspect.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let w = parts.first.flatMap(Double.init), w > 0 else { return nil }
        if parts.count == 1 { return w }
        guard parts.count == 2, let h = Double(parts[1]), h > 0 else { return nil }
        return w / h
    }
}

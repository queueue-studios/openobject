import SwiftUI
import UIKit
import DisplayCore

// Renders one piece of ready media on the zero-chrome stage (§6): a still, an animated image (its
// frames walked over their per-frame delays), or a looping video. Fit letterboxes against the bare
// black stage (contain); Fill covers and center-crops (cover) — matching the web display.
struct MediaView: View {
    let media: RenderableMedia
    let fit: Fit
    let muted: Bool
    let audioBus: AudioBus

    var body: some View {
        switch media {
        case .still(let image):
            StageImage(cgImage: image.cgImage, fit: fit)
        case .animated(let animated):
            AnimatedImageView(animated: animated, fit: fit)
        case .video(let url):
            VideoLayerView(url: url, fit: fit, muted: muted, bus: audioBus)
        }
    }
}

// One image sized to the full stage: Fit letterboxes (contain), Fill covers and center-crops (cover).
// The crop MUST be symmetric so a centered subject stays centered. Sizing the image with an explicit
// stage-sized frame (from GeometryReader) does that; the earlier `.aspectRatio(.fill)` over a flexible
// `.frame(maxWidth/maxHeight: .infinity)` shifted the image off-center on tvOS (a centered subject drifted
// right), because the flexible frame did not center the overflow symmetrically (§6).
private struct StageImage: View {
    let cgImage: CGImage
    let fit: Fit

    var body: some View {
        GeometryReader { geo in
            Image(decorative: cgImage, scale: 1, orientation: .up)
                .resizable()
                .aspectRatio(contentMode: fit == .fill ? .fill : .fit)
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }
}

// Walks an AnimatedImage's frames on its own timeline. TimelineView(.animation) ticks each display
// refresh; the frame is derived from elapsed time modulo the total duration, and AnimatedImage decodes
// each frame on demand behind a small rolling buffer (§9), so nothing holds the whole animation.
private struct AnimatedImageView: View {
    let animated: AnimatedImage
    let fit: Fit
    private let start = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let index = frameIndex(elapsed: context.date.timeIntervalSince(start))
            if let cgImage = animated.frame(at: index) {
                StageImage(cgImage: cgImage, fit: fit)
            } else {
                Color.black
            }
        }
    }

    private func frameIndex(elapsed: TimeInterval) -> Int {
        let total = animated.totalDuration
        guard total > 0 else { return 0 }
        var t = elapsed.truncatingRemainder(dividingBy: total)
        for (i, delay) in animated.delays.enumerated() {
            if t < delay { return i }
            t -= delay
        }
        return max(0, animated.frameCount - 1)
    }
}

import SwiftUI
import DisplayCore

// Renders one piece of ready media on the zero-chrome stage (§6): a still, an animated image (its
// frames walked over their per-frame delays), or a looping video. Fit letterboxes against the bare
// black stage (contain); Fill covers and center-crops (cover) — matching the web display.
struct MediaView: View {
    let media: RenderableMedia
    let fit: Fit

    var body: some View {
        switch media {
        case .still(let image):
            frame(image.cgImage)
        case .animated(let animated):
            AnimatedImageView(animated: animated, fit: fit)
        case .video(let url):
            VideoLayerView(url: url, fit: fit)
        }
    }

    @ViewBuilder private func frame(_ cgImage: CGImage) -> some View {
        Image(decorative: cgImage, scale: 1, orientation: .up)
            .resizable()
            .aspectRatio(contentMode: fit == .fill ? .fill : .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
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
                Image(decorative: cgImage, scale: 1, orientation: .up)
                    .resizable()
                    .aspectRatio(contentMode: fit == .fill ? .fill : .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
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

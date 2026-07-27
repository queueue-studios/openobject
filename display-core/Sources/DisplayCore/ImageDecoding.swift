import Foundation
import CoreGraphics
import ImageIO

// Bounded, memory-safe decoding for the native Display (§9). tvOS kills hungry apps, and the risk is
// DECODED size, not file size: a 15MB still becomes tens of MB of bitmap at full resolution. So stills
// are decoded through an ImageIO thumbnail capped to the panel size, and animations (GIF/WebP/AVIS) are
// decoded on demand a few frames at a time, never the whole sequence into memory.

/// An immutable decoded bitmap, safe to hand across concurrency domains (CGImage is immutable).
public struct SendableImage: @unchecked Sendable {
    public let cgImage: CGImage
    public init(_ cgImage: CGImage) { self.cgImage = cgImage }
    public var pixelWidth: Int { cgImage.width }
    public var pixelHeight: Int { cgImage.height }
}

// The ImageIO thumbnail options shared by stills and animated frames: always produce a thumbnail,
// capped on the longest side, honoring EXIF orientation.
private func thumbnailOptions(maxPixel: Int) -> CFDictionary {
    [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        kCGImageSourceCreateThumbnailWithTransform: true,
    ] as CFDictionary
}

public enum ImageDecoder {
    /// Decode a still bounded to `maxPixel` on its longest side, so the resident bitmap is sized to the
    /// display rather than the source (§9). nil if the data is not a decodable image.
    public static func decodeStill(_ data: Data, maxPixel: Int) -> SendableImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions(maxPixel: maxPixel))
        else { return nil }
        return SendableImage(cg)
    }
}

/// An animated image (GIF/WebP/AVIS) decoded ON DEMAND: it reads the frame count and per-frame delays
/// up front (cheap) but decodes each frame's bitmap only when asked, keeping just a small rolling
/// buffer resident (§9) — the native equivalent of FLAnimatedImage. A driver (Phase C, a CADisplayLink)
/// walks `frame(at:)` on the delays. Thread-safe via a lock, hence @unchecked Sendable.
public final class AnimatedImage: @unchecked Sendable {
    public let frameCount: Int
    public let delays: [Double]              // seconds per frame
    public var totalDuration: Double { delays.reduce(0, +) }

    private let source: CGImageSource
    private let maxPixel: Int
    private let bufferSize: Int
    private let lock = NSLock()
    private var buffer: [Int: CGImage] = [:]
    private var recent: [Int] = []           // LRU order of buffered frame indices

    /// - Returns: nil if the data is not a decodable image sequence.
    public init?(data: Data, maxPixel: Int, bufferSize: Int = 8) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }
        self.source = source
        self.maxPixel = maxPixel
        self.bufferSize = max(1, bufferSize)
        self.frameCount = count
        self.delays = (0..<count).map { AnimatedImage.frameDelay(source, $0) }
    }

    /// The bitmap for `index` (wrapping out-of-range), decoding on demand and keeping at most
    /// `bufferSize` frames resident.
    public func frame(at index: Int) -> CGImage? {
        let i = ((index % frameCount) + frameCount) % frameCount
        lock.lock(); defer { lock.unlock() }
        if let cached = buffer[i] { return cached }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, i, thumbnailOptions(maxPixel: maxPixel)) else {
            return nil
        }
        buffer[i] = cg
        recent.append(i)
        if recent.count > bufferSize { buffer[recent.removeFirst()] = nil }
        return cg
    }

    /// How many frames are currently resident (for tests / diagnostics).
    public var bufferedFrameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return buffer.count
    }

    // Per-frame delay from the format's metadata (GIF, WebP, or animated AVIF), preferring the unclamped
    // value; a sane default when a format omits it. The AVIS (animated AVIF) dictionary carries its delay
    // under the same "DelayTime"/"UnclampedDelayTime" keys as GIF (confirmed on-device, Phase C, §6), so
    // the same key constants read it; without this an animated AVIF would play at the 0.1s fallback.
    private static func frameDelay(_ source: CGImageSource, _ index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return 0.1
        }
        for dictKey in [kCGImagePropertyGIFDictionary, kCGImagePropertyWebPDictionary, kCGImagePropertyAVISDictionary] {
            guard let dict = props[dictKey] as? [CFString: Any] else { continue }
            let unclamped = (dict[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                ?? (dict[kCGImagePropertyWebPUnclampedDelayTime] as? Double)
            let clamped = (dict[kCGImagePropertyGIFDelayTime] as? Double)
                ?? (dict[kCGImagePropertyWebPDelayTime] as? Double)
            if let delay = unclamped ?? clamped, delay > 0 { return delay }
        }
        return 0.1
    }
}

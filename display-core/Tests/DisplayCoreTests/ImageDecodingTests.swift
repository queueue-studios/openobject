import Testing
import Foundation
@testable import DisplayCore

@Suite struct ImageDecodingTests {
    @Test func decodesStillBoundedToMaxPixel() throws {
        let data = TestImages.pngData(width: 4000, height: 2000)      // a big source
        let image = try #require(ImageDecoder.decodeStill(data, maxPixel: 512))
        #expect(max(image.pixelWidth, image.pixelHeight) <= 512)      // capped to the panel, not 4000px
        #expect(image.pixelWidth > 0 && image.pixelHeight > 0)
    }

    @Test func animatedReadsFramesAndDelaysAndBuffersFew() throws {
        let data = TestImages.animatedGIFData(frames: 12, size: 200, delay: 0.05)
        let animated = try #require(AnimatedImage(data: data, maxPixel: 64, bufferSize: 4))
        #expect(animated.frameCount == 12)
        #expect((animated.totalDuration - 0.6).magnitude < 0.06)      // ~ 12 * 0.05s

        let frame0 = try #require(animated.frame(at: 0))
        #expect(max(frame0.width, frame0.height) <= 64)              // frames are bounded too

        for i in 0..<12 { _ = animated.frame(at: i) }                // walk the whole animation
        #expect(animated.bufferedFrameCount <= 4)                    // rolling buffer, never all 12
    }

    @Test func wrapsFrameIndex() throws {
        let animated = try #require(AnimatedImage(data: TestImages.animatedGIFData(frames: 3, size: 32, delay: 0.1), maxPixel: 32))
        #expect(animated.frame(at: 4) != nil)                         // 4 % 3 -> frame 1
        #expect(animated.frame(at: -1) != nil)                        // wraps negative too
    }

    @Test func returnsNilForNonImageData() {
        #expect(ImageDecoder.decodeStill(Data("not an image".utf8), maxPixel: 100) == nil)
        #expect(AnimatedImage(data: Data("nope".utf8), maxPixel: 100) == nil)
    }
}

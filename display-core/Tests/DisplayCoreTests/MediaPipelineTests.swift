import Testing
import Foundation
@testable import DisplayCore

@Suite struct MediaPipelineTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("oo-pipe-\(UUID().uuidString)")
    }

    // A cache whose "network" serves generated media by file extension.
    private func stubCache(_ dir: URL) -> MediaCache {
        MediaCache(directory: dir, capBytes: 10_000_000) { url in
            switch url.pathExtension {
            case "png": return TestImages.pngData(width: 2000, height: 1000)
            case "gif": return TestImages.animatedGIFData(frames: 6, size: 100, delay: 0.05)
            case "mp4": return Data(repeating: 0, count: 1234)      // bytes only; never decoded
            default: return Data()
            }
        }
    }

    @Test func mediaURLResolvesUploadsAndFolderSrc() throws {
        let host = try #require(DisplayCore.Host.manualEntry("192.168.1.42:3000"))
        let pipeline = MediaPipeline(cache: stubCache(tempDir()))
        let upload = DisplayItem(id: "1", kind: .still, format: .png, fit: .fit, filename: "a.png", src: nil)
        let folder = DisplayItem(id: "fc1:b.mp4", kind: .video, format: .mp4, fit: .fill,
                                 filename: "b.mp4", src: "/folder-media/1/b.mp4")
        #expect(pipeline.mediaURL(for: upload, on: host)?.absoluteString == "http://192.168.1.42:3000/uploads/a.png")
        #expect(pipeline.mediaURL(for: folder, on: host)?.absoluteString == "http://192.168.1.42:3000/folder-media/1/b.mp4")
    }

    @Test func loadsStillAnimatedAndVideo() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let host = try #require(DisplayCore.Host.manualEntry("h:3000"))
        let pipeline = MediaPipeline(cache: stubCache(dir), maxPixel: 256)

        let still = try await pipeline.load(
            DisplayItem(id: "1", kind: .still, format: .png, fit: .fit, filename: "a.png", src: nil), from: host)
        guard case let .still(image) = still else { Issue.record("expected still"); return }
        #expect(max(image.pixelWidth, image.pixelHeight) <= 256)      // decoded bounded

        let animated = try await pipeline.load(
            DisplayItem(id: "2", kind: .animated, format: .gif, fit: .fit, filename: "b.gif", src: nil), from: host)
        guard case let .animated(anim) = animated else { Issue.record("expected animated"); return }
        #expect(anim.frameCount == 6)

        let video = try await pipeline.load(
            DisplayItem(id: "3", kind: .video, format: .mp4, fit: .fit, filename: "c.mp4", src: nil), from: host)
        guard case let .video(url) = video else { Issue.record("expected video"); return }
        #expect(FileManager.default.fileExists(atPath: url.path))     // a local file for AVPlayer
    }

    @Test func prefetchWarmsTheCache() async throws {
        let dir = tempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let host = try #require(DisplayCore.Host.manualEntry("h:3000"))
        let cache = stubCache(dir)
        let pipeline = MediaPipeline(cache: cache)
        let item = DisplayItem(id: "1", kind: .still, format: .png, fit: .fit, filename: "a.png", src: nil)
        #expect(await cache.usage().count == 0)
        await pipeline.prefetch(item, from: host)
        #expect(await cache.usage().count == 1)                       // next piece warmed ahead of the crossfade
    }
}

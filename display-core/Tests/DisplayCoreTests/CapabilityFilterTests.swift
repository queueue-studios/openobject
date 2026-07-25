import Testing
@testable import DisplayCore

@Suite struct CapabilityFilterTests {
    let filter = CapabilityFilter()

    @Test func rendersStillsAnimatedAndVideo() {
        #expect(filter.canRender(kind: .still, format: .jpeg))
        #expect(filter.canRender(kind: .still, format: .png))
        #expect(filter.canRender(kind: .animated, format: .gif))
        #expect(filter.canRender(kind: .animated, format: .webp))
        #expect(filter.canRender(kind: .animated, format: .avif))
        #expect(filter.canRender(kind: .video, format: .mp4))
        #expect(filter.canRender(kind: .video, format: .mov))
    }

    @Test func skipsSvgAndWebm() {
        #expect(!filter.canRender(kind: .animated, format: .svg))
        #expect(!filter.canRender(kind: .video, format: .webm))
    }

    @Test func skipsConnectedRegardlessOfFormat() {
        #expect(!filter.canRender(kind: .connected, format: nil))
        #expect(!filter.canRender(kind: .connected, format: .jpeg)) // never, even if a format sneaks in
    }

    @Test func skipsWhenFormatUnknown() {
        #expect(!filter.canRender(kind: .still, format: nil))
    }

    @Test func formatKindMappingMirrorsFormatsJs() {
        #expect(MediaFormat.jpeg.kind == .still)
        #expect(MediaFormat.svg.kind == .animated)
        #expect(MediaFormat.mov.kind == .video)
    }
}

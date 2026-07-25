import Testing
@testable import DisplayCore

// Guards the format table (mirrors player/src/formats.js) and the tvOS render policy, so a drift in
// either is caught here rather than on a device.
@Suite struct FormatPolicyTests {
    @Test func nineFormatsEachMapToAKind() {
        #expect(MediaFormat.allCases.count == 9)
        for format in MediaFormat.allCases { _ = format.kind } // total mapping: no missing case
    }

    @Test func renderPolicyDeclinesOnlySvgAndWebm() {
        let declined = Set(MediaFormat.allCases).subtracting(CapabilityFilter.renderableFormats)
        #expect(declined == [.svg, .webm]) // everything else renders on tvOS (§6)
    }
}

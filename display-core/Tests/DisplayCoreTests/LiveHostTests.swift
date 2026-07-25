import Testing
import Foundation
@testable import DisplayCore

// Opt-in live integration against a REAL running Host. Skipped unless OO_LIVE_HOST is set (e.g.
// `OO_LIVE_HOST=localhost:3010 swift test`), so the normal suite stays hermetic and offline. Proves the
// client + decoder handle a live /api/display end to end, not just captured fixtures.
@Suite struct LiveHostTests {
    // Qualified as DisplayCore.Host: on macOS (where tests run) Foundation also exposes a deprecated
    // `Host` (NSHost), so a bare `Host` type annotation is ambiguous here. No such type exists on
    // tvOS/iOS, so the app never needs this qualification.
    static var liveHost: DisplayCore.Host? {
        ProcessInfo.processInfo.environment["OO_LIVE_HOST"].flatMap(DisplayCore.Host.manualEntry)
    }

    @Test(.enabled(if: LiveHostTests.liveHost != nil))
    func fetchesFromRealHost() async throws {
        let host = try #require(Self.liveHost)
        let response = try await DisplayClient().fetchDisplay(from: host)
        // Content varies with the owner's rotation; assert only that a valid response decoded.
        #expect(response.source == .library || response.source == .folder)
    }
}

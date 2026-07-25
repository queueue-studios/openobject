import Testing
import Foundation
@testable import DisplayCore

// Opt-in live integration: browses the real LAN and, if it finds an OpenObject Host, fetches
// /api/display from it end to end. Skipped unless OO_DISCOVER=1, so the normal suite stays hermetic
// (and doesn't depend on multicast being available). Run with a Host advertising, e.g. the preview
// server or a real frame: `OO_DISCOVER=1 swift test --filter LiveDiscoveryTests`.
@Suite struct LiveDiscoveryTests {
    static var enabled: Bool { ProcessInfo.processInfo.environment["OO_DISCOVER"] == "1" }

    @Test(.enabled(if: LiveDiscoveryTests.enabled))
    @MainActor
    func discoversAHostAndFetchesFromIt() async throws {
        let discovery = HostDiscovery()
        discovery.start()
        defer { discovery.stop() }

        // Give Bonjour up to ~10s to find and resolve a Host. Qualified as DisplayCore.Host because on
        // macOS (where tests run) Foundation also exposes a deprecated `Host` (NSHost).
        var found: DisplayCore.Host?
        for _ in 0..<100 {
            if let host = discovery.hosts.first { found = host; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let host = try #require(found, "no _openobject._tcp Host discovered on the LAN")

        // End to end: the discovered Host's baseURL yields a valid /api/display.
        let response = try await DisplayClient().fetchDisplay(from: host)
        #expect(response.source == .library || response.source == .folder)
    }
}

import Testing
import Foundation
@testable import DisplayCore

@Suite struct HostTests {
    @Test func manualEntryBareHostImpliesHttp() {
        let h = Host.manualEntry("openobject.local")
        #expect(h?.baseURL.absoluteString == "http://openobject.local")
        #expect(h?.baseURL.port == nil) // standard http port, correct for the frame (PORT=80)
        #expect(h?.name == "openobject.local")
    }

    @Test func manualEntryHostAndPort() {
        let h = Host.manualEntry("192.168.1.42:3000")
        #expect(h?.baseURL.absoluteString == "http://192.168.1.42:3000")
        #expect(h?.baseURL.port == 3000)
    }

    @Test func manualEntryFullURLKeepsOriginDropsPath() {
        let h = Host.manualEntry("http://192.168.1.42:3000/display?x=1")
        #expect(h?.baseURL.absoluteString == "http://192.168.1.42:3000")
    }

    @Test func manualEntryPreservesHttps() {
        #expect(Host.manualEntry("https://example.test")?.baseURL.scheme == "https")
    }

    @Test func manualEntryTrimsWhitespace() {
        #expect(Host.manualEntry("  openobject.local  ")?.baseURL.absoluteString == "http://openobject.local")
    }

    @Test(arguments: ["", "   ", "http://"])
    func manualEntryRejectsGarbage(_ raw: String) {
        #expect(Host.manualEntry(raw) == nil)
    }

    @Test func codableRoundTrip() throws {
        let h = Host(id: "abc123", name: "Living Room",
                     baseURL: URL(string: "http://192.168.1.42:3000")!, version: "1.5.1")
        let data = try JSONEncoder().encode(h)
        let back = try JSONDecoder().decode(Host.self, from: data)
        #expect(back == h)
    }
}

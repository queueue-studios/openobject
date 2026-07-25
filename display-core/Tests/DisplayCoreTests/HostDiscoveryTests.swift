import Testing
import Foundation
@testable import DisplayCore

// Unit tests for the pure part of discovery: turning a discovered service's TXT + resolved address
// into a Host. The NWBrowser plumbing is exercised by the opt-in LiveDiscoveryTests.
@Suite struct HostDiscoveryTests {
    @Test func buildsHostFromFullTXT() {
        let host = Host.fromBonjour(
            serviceName: "svc",
            txt: ["id": "abc123", "name": "Living Room", "version": "1.5.1", "role": "host"],
            host: "192.168.1.42", port: 3000)
        #expect(host?.id == "abc123")
        #expect(host?.name == "Living Room")
        #expect(host?.version == "1.5.1")
        #expect(host?.baseURL.absoluteString == "http://192.168.1.42:3000")
    }

    @Test func omitsDefaultHttpPortLikeTheFrame() {
        let host = Host.fromBonjour(serviceName: "svc", txt: ["id": "x", "name": "Frame"],
                                    host: "openobject.local", port: 80)
        #expect(host?.baseURL.absoluteString == "http://openobject.local") // no :80
    }

    @Test func fallsBackWhenNameOrIdMissing() {
        let host = Host.fromBonjour(serviceName: "Matt's Mac", txt: ["version": "1.5.1"],
                                    host: "10.0.0.5", port: 3000)
        #expect(host?.name == "Matt's Mac")               // service name fallback
        #expect(host?.id == "http://10.0.0.5:3000")       // origin fallback when TXT has no id
        #expect(host?.version == "1.5.1")
    }

    @Test func treatsEmptyTXTValuesAsMissing() {
        let host = Host.fromBonjour(serviceName: "MyMac", txt: ["id": "", "name": "", "version": ""],
                                    host: "10.0.0.9", port: 3000)
        #expect(host?.name == "MyMac")
        #expect(host?.id == "http://10.0.0.9:3000")
        #expect(host?.version == nil)
    }
}

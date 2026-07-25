import Testing
import Foundation
@testable import DisplayCore

@Suite struct HostStoreTests {
    @Test func inMemoryStoreRoundTrips() {
        let store = InMemoryHostStore()
        #expect(store.loadDefaultHost() == nil)

        let host = Host(id: "x", name: "Frame",
                        baseURL: URL(string: "http://openobject.local")!, version: nil)
        store.saveDefaultHost(host)
        #expect(store.loadDefaultHost() == host)

        store.saveDefaultHost(nil)
        #expect(store.loadDefaultHost() == nil)
    }

    @Test func seedsFromInitialValue() {
        let host = Host(id: "y", name: "Studio",
                        baseURL: URL(string: "http://192.168.1.50:3000")!, version: "1.5.1")
        #expect(InMemoryHostStore(host).loadDefaultHost() == host)
    }
}

import Testing
import Foundation
@testable import DisplayCore

// Stubs URLSession so DisplayClient is tested with no real network. Serialized because the stub uses a
// shared handler (Swift Testing runs tests in parallel by default).
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.handler?(request) ?? (500, Data())
        let resp = HTTPURLResponse(url: request.url!, statusCode: status,
                                   httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct DisplayClientTests {
    private func makeClient() -> DisplayClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return DisplayClient(session: URLSession(configuration: config))
    }

    @Test func fetchesApiDisplayPathAndDecodes() async throws {
        let body = Data("""
        {"items":[{"id":1,"filename":"a.png","format":"png","kind":"still","fit":"fit"}],
         "durationMs":8000,"mode":"sequence","pinnedId":null,"asleep":false,"source":"library"}
        """.utf8)
        MockURLProtocol.handler = { req in
            #expect(req.url?.path == "/api/display") // resolves against the Host's baseURL
            return (200, body)
        }
        let host = try #require(Host.manualEntry("192.168.1.42:3000"))
        let r = try await makeClient().fetchDisplay(from: host)
        #expect(r.items.count == 1)
        #expect(r.items[0].id == "1")
        #expect(r.items[0].isRenderable())
    }

    @Test func throwsOnHttpError() async throws {
        MockURLProtocol.handler = { _ in (500, Data("boom".utf8)) }
        let host = try #require(Host.manualEntry("192.168.1.42:3000"))
        await #expect(throws: DisplayClientError.httpStatus(500)) {
            try await makeClient().fetchDisplay(from: host)
        }
    }
}

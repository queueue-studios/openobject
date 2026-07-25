import Foundation

// The HTTP client for a Host's Display API: it fetches /api/display and decodes it. The rotation engine
// (B4) drives the ~5s polling that folds changes in without restarting the loop. Every request resolves
// against the Host's baseURL — the native equivalent of a browser display's same-origin fetches (§3) —
// and the Host is unchanged, with no tvOS-specific endpoint (§11).

public enum DisplayClientError: Error, Sendable, Equatable {
    /// The response was not HTTP (should not happen for http(s) URLs).
    case notHTTP
    /// The Host answered with a non-2xx status.
    case httpStatus(Int)
}

public struct DisplayClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch and decode the Host's current rotation. Throws `DisplayClientError` on a bad HTTP status,
    /// a `URLError` on a network failure (a manually-typed address that does not answer, §13), or a
    /// `DecodingError` if the body is not a valid /api/display response.
    public func fetchDisplay(from host: Host) async throws -> DisplayResponse {
        let url = host.baseURL.appending(path: "api/display")
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw DisplayClientError.notHTTP }
        guard (200..<300).contains(http.statusCode) else {
            throw DisplayClientError.httpStatus(http.statusCode)
        }
        return try JSONDecoder().decode(DisplayResponse.self, from: data)
    }
}

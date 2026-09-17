import Foundation
import WebKit
import UniformTypeIdentifiers
import CryptoKit
import os
import DisplayCore

// Serves a Connected piece's held bundle to the web view when the Host is not there (HANDOFF §17 "Connected
// Collections on the viewer apps", phase two, 2026-09-17). WebKit blocks a page's own fetches from plain
// file paths (inkField loads its recording that way), so the copy is served through a custom URL scheme
// instead: the piece's URL keeps display.js's whole contract with `oo-copy://copy` as its origin, so
//   oo-copy://copy/collections/<slug>[/<token>]/<path>
// maps onto the bundle directory the local copy holds for that piece. One origin for the whole copy means
// the bundle's sessionStorage flag, relative fetches, query seed and fragment all behave as on the Host.
// Media gets byte ranges, because WebKit's players request them and give up on a server that ignores them.
final class CopySchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "oo-copy"
    static let base = URL(string: "oo-copy://copy")!

    /// The directory holding the bundle for a slug and optional token, or nil if the copy does not hold it.
    typealias Resolver = @MainActor (_ slug: String, _ token: String?) -> URL?
    private let resolve: Resolver
    private static let log = Logger(subsystem: "io.openobject.app", category: "webview")

    init(resolve: @escaping Resolver) { self.resolve = resolve }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == "copy" else { return fail(task, 400) }
        // /collections/<slug>[/<token>]/<path…>: which segment is a token is the bundle layout's business, so
        // try the two-segment form (perToken) before the one-segment form (shared).
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 3, parts[0] == "collections" else { return fail(task, 404) }
        let slug = parts[1]
        Task { @MainActor in
            var file: URL?
            if parts.count >= 4, let dir = resolve(slug, parts[2]) {
                file = dir.appendingPathComponent(parts[3...].joined(separator: "/"))
            } else if let dir = resolve(slug, nil) {
                file = dir.appendingPathComponent(parts[2...].joined(separator: "/"))
            }
            guard let file else { return self.fail(task, 404) }
            // A live piece's node requests (E30): answered from the cached answers the Host kept beside the
            // bundle, keyed by the request body's hash, exactly as the Host itself answers with no internet.
            if task.request.httpMethod == "POST", file.lastPathComponent == "rpc" {
                let cacheFile = file.deletingLastPathComponent().appendingPathComponent("rpc-cache.json")
                let body = task.request.httpBody ?? Data()
                let key = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
                guard let cacheData = try? Data(contentsOf: cacheFile),
                      let cache = try? JSONSerialization.jsonObject(with: cacheData) as? [String: String],
                      let answer = cache[key] else {
                    Self.log.error("copy has no node answer for \(slug, privacy: .public) \(url.path, privacy: .public)")
                    return self.fail(task, 502)
                }
                Self.log.log("copy answered node request for \(slug, privacy: .public) from cache")
                return self.respond(task, url: url, data: Data(answer.utf8), type: "application/json", range: nil)
            }
            guard let data = try? Data(contentsOf: file, options: .mappedIfSafe) else { return self.fail(task, 404) }
            self.respond(task, url: url, data: data, type: Self.mimeType(for: file), range: task.request.value(forHTTPHeaderField: "Range"))
        }
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    private func respond(_ task: WKURLSchemeTask, url: URL, data: Data, type: String, range: String?) {
        var headers = ["Content-Type": type, "Accept-Ranges": "bytes", "Cache-Control": "no-store"]
        var body = data
        var status = 200
        if let range, range.hasPrefix("bytes=") {
            let spec = range.dropFirst("bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
            let total = data.count
            let start = Int(spec.first ?? "") ?? 0
            let end = spec.count > 1 ? (Int(spec[1]) ?? total - 1) : total - 1
            if start < total, start <= end {
                let last = min(end, total - 1)
                body = data.subdata(in: start..<(last + 1))
                headers["Content-Range"] = "bytes \(start)-\(last)/\(total)"
                status = 206
            }
        }
        headers["Content-Length"] = String(body.count)
        guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else { return fail(task, 500) }
        task.didReceive(response)
        task.didReceive(body)
        task.didFinish()
    }

    private func fail(_ task: WKURLSchemeTask, _ status: Int) {
        if let url = task.request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) {
            task.didReceive(response)
            task.didFinish()
        } else {
            task.didFailWithError(URLError(.fileDoesNotExist))
        }
    }

    static func mimeType(for file: URL) -> String {
        let ext = file.pathExtension.lowercased()
        switch ext {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "wasm": return "application/wasm"
        default:
            return UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
        }
    }
}

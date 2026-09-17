import SwiftUI
import WebKit
import AVFoundation
import os
import DisplayCore
import DisplayUI

// The iOS app's renderer for a Connected piece (HANDOFF §17 "Connected Collections on the viewer apps",
// phase one, 2026-09-16): a WKWebView pointed at the Host's own same-origin mirror of the bundle, at the
// URL display.js would build (ConnectedURL). It is what the frame's Chromium and the Mac's Chrome do with
// an iframe, with the three things a web view has to be told explicitly:
//   • autoplay with no user gesture (the kiosk's --autoplay-policy flag), so a scored piece is heard;
//   • the bundle's one-shot sessionStorage flags, set by a user script before the page's own scripts run
//     (a same-origin iframe shared the display page's storage; here the page is top-level);
//   • what the iframe sandbox gave for free: the page may not navigate anywhere but its own bundle and may
//     not open windows.
// It reports ready once the page has painted, not merely loaded: a p5 sketch's load event fires before it
// has drawn anything, so revealing on load lands the crossfade on a black canvas (seen on the real iPad
// 2026-09-16 between two sketches). display.js waits for the first painted frame only for the one
// `awaitPaint` collection; here every piece gets that wait, by the same canvas-and-frameCount test, capped
// at 12 s (a page with no sketch at all is ready as soon as it has loaded). It tells the stage when its web
// content process has died twice, the one failure a web view can have that the page cannot recover from
// itself. Each layer gets its own process pool, so the incoming piece's synchronous generate cannot stall
// the outgoing piece's animation the way same-origin iframes stall each other on the frame (the freeze
// seen alongside the black flash); the cost is a second web process during a crossfade. The page's own
// uncaught errors and rejections are bridged into the log, so a bundle that fails on a device says why.
//
// Every load, ready, death and memory warning is logged (subsystem io.openobject.app, category webview,
// persisted) so the memory budget can be read off a device in Console.app or Xcode: this build is the one
// that measures it.
struct ConnectedWebLayer: UIViewRepresentable {
    let url: URL
    let host: Host
    let item: DisplayItem
    /// Serves the local copy's bundles under the copy scheme (§17 phase two); nil for a Host with no copy.
    let copyHandler: CopySchemeHandler?
    /// The same piece from the held copy, tried once if the Host load fails: a piece picked in the seconds
    /// before a poll notices the Host is gone would otherwise fail and hold the stage until the give-up.
    let fallbackURL: URL?
    let onReady: () -> Void
    let onFailed: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = WKProcessPool()                       // its own web process: no cross-piece stalls
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []      // the kiosk's autoplay flag
        config.websiteDataStore = .default()                       // bundles cache across pieces and launches
        let content = WKUserContentController()
        if let flags = item.sessionFlags, !flags.isEmpty {
            let sets = flags.map { "try{sessionStorage.setItem(\(Self.jsString($0.key)),\(Self.jsString($0.value)))}catch(e){}" }
            content.addUserScript(WKUserScript(source: sets.joined(separator: ";"),
                                               injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        content.addUserScript(WKUserScript(source: Self.errorBridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(context.coordinator, name: Self.errorHandlerName)
        config.userContentController = content
        if let copyHandler { config.setURLSchemeHandler(copyHandler, forURLScheme: CopySchemeHandler.scheme) }

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        // Black under and around the page from the first frame (the stage is black; a white flash is the
        // web view's default background showing before the bundle paints).
        web.isOpaque = false
        web.backgroundColor = .black
        web.underPageBackgroundColor = .black
        web.scrollView.backgroundColor = .black
        // A display, not a browser: nothing scrolls, bounces, insets, previews or navigates.
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.isUserInteractionEnabled = false   // the art is not a control; the stage's tap catcher is above anyway
        context.coordinator.begin(web)
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) { coordinator.end(web) }

    static let errorHandlerName = "oolog"
    /// Uncaught errors and unhandled rejections in the page, posted to the log (never to the stage: a
    /// bundle's own error is the bundle's business, as on the frame; this is diagnosis only).
    static let errorBridge = "(function(){var p=function(m){try{window.webkit.messageHandlers.oolog.postMessage(String(m))}catch(e){}};"
        + "window.addEventListener('error',function(e){p((e.message||'error')+' @ '+(e.filename||'?')+':'+(e.lineno||0))});"
        + "window.addEventListener('unhandledrejection',function(e){p('unhandled rejection: '+(e.reason&&e.reason.message||e.reason))});})();"

    /// A JavaScript string literal for a Swift string.
    static func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())   // ["..."] -> "..."
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let parent: ConnectedWebLayer
        private var startedAt = ContinuousClock.now
        private var deaths = 0
        private var triedFallback = false
        private var reported = false
        private var paintPoll: Task<Void, Never>?
        private static let log = Logger(subsystem: "io.openobject.app", category: "webview")

        init(_ parent: ConnectedWebLayer) {
            self.parent = parent
            WebTelemetry.install()
        }

        private var label: String {
            "\(parent.item.collection ?? "?")" + (parent.item.tokenId.map { "/\($0)" } ?? "")
        }

        func begin(_ web: WKWebView) {
            startedAt = .now
            // The app's playback audio session (§10, set up at launch) is activated by a native video when it
            // starts; a scored Connected piece plays through the same session, so activate it here too, which
            // is what lets it sound with the device's silent mode on. Harmless for a silent piece. Off the main
            // thread: the session API warns that activation there can stall the UI.
            Task.detached(priority: .utility) { try? AVAudioSession.sharedInstance().setActive(true) }
            Self.log.log("load \(self.label, privacy: .public) free=\(WebTelemetry.freeMB)MB url=\(self.parent.url.absoluteString, privacy: .public)")
            web.load(URLRequest(url: parent.url))
        }

        func end(_ web: WKWebView) {
            paintPoll?.cancel()
            web.stopLoading()
            web.navigationDelegate = nil
            web.uiDelegate = nil
            web.configuration.userContentController.removeScriptMessageHandler(forName: ConnectedWebLayer.errorHandlerName)
            web.loadHTMLString("", baseURL: nil)   // release the page's resources before the view is freed
            Self.log.log("unload \(self.label, privacy: .public) free=\(WebTelemetry.freeMB)MB")
        }

        // The sandbox's intent: the main frame may only load this Host's collections; sub-frames are the
        // bundle's own business (the iframe on the frame allowed them too); no new windows, ever.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.targetFrame?.isMainFrame ?? true else { decisionHandler(.allow); return }
            if action.request.url?.scheme == CopySchemeHandler.scheme,
               action.request.url?.path.hasPrefix("/collections/") == true { decisionHandler(.allow); return }
            guard let target = action.request.url, let base = parent.host.baseURL.host,
                  target.host?.lowercased() == base.lowercased(),
                  (target.port ?? Self.defaultPort(target)) == (parent.host.baseURL.port ?? Self.defaultPort(parent.host.baseURL)),
                  target.path.hasPrefix("/collections/") else {
                Self.log.log("blocked navigation \(self.label, privacy: .public) to \(action.request.url?.absoluteString ?? "?", privacy: .public)")
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private static func defaultPort(_ url: URL) -> Int { url.scheme?.lowercased() == "https" ? 443 : 80 }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            Self.log.error("page error on \(self.label, privacy: .public): \(String(describing: message.body), privacy: .public)")
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let ms = Int(startedAt.duration(to: .now).components.seconds * 1000
                         + startedAt.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
            Self.log.log("loaded \(self.label, privacy: .public) in \(ms)ms free=\(WebTelemetry.freeMB)MB")
            waitForPaint(webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Self.log.error("failed \(self.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }

        // The page could not even start (the Host gone, most often). From the held copy if there is one, at
        // once; otherwise this piece cannot paint, so give up its turn now rather than at the 30 s give-up
        // (the next poll drops it from the rotation anyway while the Host is away).
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Self.log.error("failed \(self.label, privacy: .public): \(error.localizedDescription, privacy: .public)")
            if let fallback = parent.fallbackURL, !triedFallback {
                triedFallback = true
                Self.log.log("fallback \(self.label, privacy: .public) to \(fallback.absoluteString, privacy: .public)")
                startedAt = .now
                webView.load(URLRequest(url: fallback))
            } else {
                parent.onFailed()
            }
        }

        // The hard signal for the memory budget: iOS killed the page's process. Reload once; on the second
        // death hand the piece back to the stage, which moves on.
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            deaths += 1
            Self.log.fault("web content process died (\(self.deaths)) on \(self.label, privacy: .public) free=\(WebTelemetry.freeMB)MB")
            if deaths == 1 {
                reported = false
                startedAt = .now
                webView.reload()
            } else {
                parent.onFailed()
            }
        }

        // display.js waitForPaint, applied to every piece: a p5 sketch is ready once its canvas exists and its
        // frame count has passed the first draw (or it drew once and stopped looping). The count is read from
        // the p5 instance, not the page's global `frameCount`: inkField keeps a page-level variable of that
        // name at zero while its instance runs (measured: instance at 347, global at 0), which held it at the
        // cap. A page whose p5 has not yet built its sketch keeps waiting; any other page is ready once it has
        // a canvas or has none to wait for; anything unreadable counts as ready. Capped so a piece that never
        // paints reveals a few seconds later rather than never.
        private func waitForPaint(_ web: WKWebView) {
            paintPoll?.cancel()
            let js = "(function(){try{var c=document.querySelector('canvas');"
                + "var i=(typeof p5!=='undefined')&&p5.instance;"
                + "if(i){if(!c)return false;var f=i.frameCount;return f>=2||(f>=1&&i._loop===false)}"
                + "if(typeof frameCount==='number'){return !!c&&frameCount>=2}"
                + "if(c){return true}"
                + "return typeof p5==='undefined'}catch(e){return true}})()"
            paintPoll = Task { [weak self, weak web] in
                let cap = ContinuousClock.now.advanced(by: .seconds(12))
                while !Task.isCancelled, ContinuousClock.now < cap {
                    guard let web else { return }
                    let painted = (try? await web.evaluateJavaScript(js)) as? Bool ?? true
                    if painted { break }
                    try? await Task.sleep(for: .milliseconds(50))
                }
                guard !Task.isCancelled else { return }
                self?.ready()
            }
        }

        private func ready() {
            guard !reported else { return }
            reported = true
            let ms = Int(startedAt.duration(to: .now).components.seconds * 1000
                         + startedAt.duration(to: .now).components.attoseconds / 1_000_000_000_000_000)
            Self.log.log("ready \(self.label, privacy: .public) at \(ms)ms free=\(WebTelemetry.freeMB)MB")
            parent.onReady()
        }
    }
}

/// App-wide web-view telemetry: the app process's remaining memory budget (the web content process is a
/// separate process, invisible from here; its death is logged by the layer) and memory warnings.
@MainActor
enum WebTelemetry {
    private static var installed = false
    private static let log = Logger(subsystem: "io.openobject.app", category: "webview")

    static func install() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                log.fault("memory warning free=\(freeMB)MB")
            }
        }
    }

    /// The app's remaining memory before iOS would terminate it, in MB.
    static var freeMB: Int { Int(os_proc_available_memory() / (1024 * 1024)) }
}

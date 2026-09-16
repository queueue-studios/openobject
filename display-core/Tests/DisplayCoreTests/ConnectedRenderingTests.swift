import Testing
import Foundation
@testable import DisplayCore

// Connected Collections on the iOS app (HANDOFF §17, phase one, 2026-09-16): the wire fields decode, the
// bundle URL matches display.js byte for byte, the filter opt-in rotates through Connected pieces, and the
// player drops them while the Host is not answering and re-times a piece from its reveal.
@Suite struct ConnectedRenderingTests {
    private func host() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("frame.local")) }

    private func bloom(controls: [String: String]? = ["music": "on"]) -> DisplayItem {
        DisplayItem(id: "4", kind: .connected, format: nil, fit: .fit, filename: "oo-connected-chazstract-28",
                    collection: "chazstract", tokenId: "28",
                    sourceURL: "ipfs://bafybeih775eqj47itktjw7wqepdl5az5wupltwptc7zqaohqwrawbmiwcq",
                    controls: controls, aspect: "1920 / 1080")
    }

    // MARK: decoding

    @Test func decodesTheConnectedFieldsFromACapture() throws {
        let r = try loadDisplayFixture("display-library")
        let piece = r.items[0]
        #expect(piece.kind == .connected)
        #expect(piece.collection == "chazstract")
        #expect(piece.tokenId == "28")
        #expect(piece.sourceURL?.hasPrefix("ipfs://") == true)
        #expect(piece.controls == ["music": "on"])
        #expect(piece.aspect == "1920 / 1080")
        #expect(piece.perToken == false)
        #expect(piece.animate == false)
        #expect(piece.speed == nil && piece.choice == nil && piece.rpcUrl == nil && piece.crop == nil)
        // Renderable only where the filter opts in.
        #expect(piece.isRenderable() == false)
        #expect(piece.isRenderable(using: CapabilityFilter(rendersConnected: true)))
        // Uploads carry none of it.
        #expect(r.items[1].collection == nil && r.items[1].controls == nil && r.items[1].perToken == false)
    }

    @Test func decodesNumbersTheWayJavaScriptSpellsThem() throws {
        let json = Data("""
        {"items":[{"id":12,"kind":"connected","format":"connected","fit":"fill","collection":"bouncing-openobject-logo",
          "token_id":1,"source_url":"https://x.test/?seed=abc#7","perToken":true,"animate":true,"speed":1,"choice":0,
          "controls":{"speed":2.5,"size":20,"corner":"bounce","flag":true},"rpcUrl":"https://rpc.test/v1",
          "crop":0.6,"aspect":"3 / 2","framePixelDensity":1,"sessionFlags":{"_inkForceLive":"1"},"awaitPaint":true}],
         "durationMs":8000,"mode":"sequence","pinnedId":null,"asleep":false,"source":"library"}
        """.utf8)
        let piece = try JSONDecoder().decode(DisplayResponse.self, from: json).items[0]
        #expect(piece.tokenId == "1")
        #expect(piece.choice == "0")
        #expect(piece.speed == 1)
        #expect(piece.controls == ["speed": "2.5", "size": "20", "corner": "bounce", "flag": "true"])
        #expect(piece.perToken && piece.animate && piece.awaitPaint)
        #expect(piece.crop == 0.6)
        #expect(piece.framePixelDensity == 1)
        #expect(piece.sessionFlags == ["_inkForceLive": "1"])
        #expect(piece.rpcUrl == "https://rpc.test/v1")
    }

    @Test func connectedFieldsSurviveTheManifestRoundTrip() throws {
        let piece = DisplayItem(id: "9", kind: .connected, format: nil, fit: .fit,
                                collection: "inkfield", tokenId: "38", sourceURL: "https://ink.test/index.html#38",
                                perToken: false, animate: true, speed: 2, choice: "tiled-low",
                                controls: ["music": "off"], rpcUrl: "https://rpc.test", crop: 0.6, aspect: "1 / 1",
                                framePixelDensity: 1, sessionFlags: ["_inkForceLive": "1"], awaitPaint: true)
        let data = try JSONEncoder().encode(libraryResponse([piece]))
        let back = try JSONDecoder().decode(DisplayResponse.self, from: data)
        #expect(back.items[0] == piece)
    }

    // MARK: the URL contract (display.js render())

    @Test func bloomURLCarriesItsMusicControlAndTheSoundGate() throws {
        let h = try host()
        #expect(ConnectedURL.url(for: bloom(), on: h, phone: false, muted: false)?.absoluteString
                == "http://frame.local/collections/chazstract/index.html?oo_music=on")
        // Sound Off forces the audio control silent (§12), and nothing else changes.
        #expect(ConnectedURL.url(for: bloom(), on: h, phone: false, muted: true)?.absoluteString
                == "http://frame.local/collections/chazstract/index.html?oo_music=off")
        // Already silent: unchanged either way.
        #expect(ConnectedURL.path(for: bloom(controls: ["music": "off"]), phone: false, muted: false)
                == "/collections/chazstract/index.html?oo_music=off")
        // No controls at all: no query.
        #expect(ConnectedURL.path(for: bloom(controls: nil), phone: true, muted: true)
                == "/collections/chazstract/index.html")
    }

    @Test func hashSeededBundleKeepsItsFragmentLastAndPhonesGetTheDensity() {
        let ink = DisplayItem(id: "31", kind: .connected, format: nil, collection: "inkfield", tokenId: "38",
                              sourceURL: "https://inkfield.test/index.html#38", framePixelDensity: 1,
                              sessionFlags: ["_inkForceLive": "1"])
        #expect(ConnectedURL.path(for: ink, phone: true, muted: false) == "/collections/inkfield/index.html?_pix:1#38")
        #expect(ConnectedURL.path(for: ink, phone: false, muted: false) == "/collections/inkfield/index.html#38")
    }

    @Test func perTokenBundleWithSeedQuerySpeedAndChoice() {
        let squiggle = DisplayItem(id: "20", kind: .connected, format: nil, collection: "chromie-squiggle",
                                   tokenId: "1234", sourceURL: "https://gen.test/1234?seed=abc&n=2", perToken: true,
                                   speed: 1, choice: "0", aspect: "3 / 2")
        #expect(ConnectedURL.path(for: squiggle, phone: false, muted: false)
                == "/collections/chromie-squiggle/1234/index.html?seed=abc&n=2&oospeed=1&oochoice=0")
    }

    @Test func liveRpcAnimateAndGeneralControlsInDisplayJsOrder() {
        let logo = DisplayItem(id: "1", kind: .connected, format: nil, collection: "bouncing-openobject-logo",
                               tokenId: "1", sourceURL: "https://logo.test/", animate: true,
                               controls: ["speed": "2.5", "size": "20", "corner": "bounce"],
                               rpcUrl: "https://rpc.test/v1?key=a b")
        #expect(ConnectedURL.path(for: logo, phone: false, muted: false)
                == "/collections/bouncing-openobject-logo/index.html?rpc_url=https%3A%2F%2Frpc.test%2Fv1%3Fkey%3Da%20b&ooanim=1&oo_corner=bounce&oo_size=20&oo_speed=2.5")
        // Not a Connected piece: no URL.
        #expect(ConnectedURL.path(for: item("u"), phone: false, muted: false) == nil)
    }

    @Test func encodeMatchesEncodeURIComponent() {
        #expect(ConnectedURL.encode("a-b_c.d!e~f*g'h(i)") == "a-b_c.d!e~f*g'h(i)")
        #expect(ConnectedURL.encode("x y/z?&=#é") == "x%20y%2Fz%3F%26%3D%23%C3%A9")
    }

    // MARK: the engine with the opt-in filter

    @Test func engineRotatesThroughConnectedPiecesOnlyWithTheOptIn() {
        let response = libraryResponse([bloom(), item("n")])
        let native = RotationEngine()
        native.apply(response)
        #expect(playingID(native) == "n")               // tvOS: the Connected piece is skipped
        let web = RotationEngine(filter: CapabilityFilter(rendersConnected: true))
        web.apply(response)
        #expect(playingID(web) == "4")                  // iOS: it plays in turn
        #expect(web.autoAdvances)
        web.advance()
        #expect(playingID(web) == "n")
    }

    @Test func aControlChangeRestylesTheConnectedPieceInPlace() {
        let web = RotationEngine(filter: CapabilityFilter(rendersConnected: true))
        web.apply(libraryResponse([bloom(), item("n")]))
        #expect(web.screen == .playing(bloom()))
        web.apply(libraryResponse([bloom(controls: ["music": "off"]), item("n")]))
        #expect(web.screen == .playing(bloom(controls: ["music": "off"])))   // same piece, new params
    }

    @Test func withoutConnectedDropsThePiecesAndAConnectedPin() {
        let r = DisplayResponse(items: [bloom(), item("n")], pinnedId: "4")
        #expect(r.hasConnected)
        let offline = r.withoutConnected
        #expect(offline.items.map(\.id) == ["n"])
        #expect(offline.pinnedId == nil)
        #expect(!offline.hasConnected)
        let pinnedNative = DisplayResponse(items: [bloom(), item("n")], pinnedId: "n").withoutConnected
        #expect(pinnedNative.pinnedId == "n")
    }
}

// The player half, on the main actor like RotationPlayerTests.
@Suite @MainActor struct ConnectedPlayerTests {
    private actor Switch {
        var failing = false
        func set(_ v: Bool) { failing = v }
    }
    private func host() throws -> DisplayCore.Host { try #require(DisplayCore.Host.manualEntry("h:3000")) }
    private func playingID(_ player: RotationPlayer) -> String? {
        if case let .playing(item) = player.screen { return item.id }
        return nil
    }
    private func waitUntil(_ timeout: Duration = .seconds(3), _ condition: @MainActor () -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
    private func connected(_ id: String) -> DisplayItem {
        DisplayItem(id: id, kind: .connected, format: nil, collection: "chazstract", sourceURL: "ipfs://x")
    }
    private func webPlayer(fetch: @escaping @Sendable (DisplayCore.Host) async throws -> DisplayResponse,
                           durationMs: Int = 100_000) -> RotationPlayer {
        let player = RotationPlayer(fetch: fetch,
                                    engine: RotationEngine(filter: CapabilityFilter(rendersConnected: true)),
                                    pollInterval: .milliseconds(20))
        player.dropsConnectedWhenHostUnreachable = true
        return player
    }

    @Test func connectedPiecesDropWhileTheHostIsGoneAndReturnWithIt() async throws {
        let live = libraryResponse([connected("c"), item("n")], durationMs: 100_000)
        let sw = Switch()
        let player = webPlayer(fetch: { _ in
            if await sw.failing { throw URLError(.cannotConnectToHost) }
            return live
        })
        player.start(host: try host())
        await waitUntil { playingID(player) == "c" }
        #expect(playingID(player) == "c")                   // live: the Connected piece plays first
        await sw.set(true)
        await waitUntil { playingID(player) == "n" }
        #expect(playingID(player) == "n")                   // gone: it is dropped, the native piece plays
        #expect(!player.hostReachable)
        await sw.set(false)
        await waitUntil { player.hostReachable }
        player.advanceNow()                                 // back: the next pick is the Connected piece
        #expect(playingID(player) == "c")
        player.stop()
    }

    @Test func aSeededOfflineStartNeverHoldsConnectedPieces() async throws {
        // The local copy's seed is already Connected-free (its wanted set uses the default filter), so a
        // Host that never answers plays the copy as seeded.
        let seed = libraryResponse([item("n")], durationMs: 100_000)
        let player = webPlayer(fetch: { _ in throw URLError(.cannotConnectToHost) })
        player.start(host: try host(), seed: seed)
        #expect(playingID(player) == "n")
        try? await Task.sleep(for: .milliseconds(80))
        #expect(playingID(player) == "n")
        player.stop()
    }

    @Test func revealReTimesTheCurrentPiece() async throws {
        let two = libraryResponse([item("1"), item("2")], durationMs: 200)
        let player = RotationPlayer(fetch: { _ in two }, pollInterval: .seconds(100))
        player.start(host: try host())
        await waitUntil { playingID(player) == "1" }
        try? await Task.sleep(for: .milliseconds(150))
        player.pieceRevealed(id: "1")                        // counted from now: 200 ms more
        try? await Task.sleep(for: .milliseconds(120))       // 270 ms after the pick, 120 after the reveal
        #expect(playingID(player) == "1")                    // not yet advanced
        await waitUntil { playingID(player) == "2" }
        #expect(playingID(player) == "2")
        player.pieceRevealed(id: "1")                        // a stale reveal is ignored
        player.stop()
    }

    @Test func advanceNowMovesOnAtOnceAndALonePieceStays() async throws {
        let two = libraryResponse([item("1"), item("2")], durationMs: 100_000)
        let player = RotationPlayer(fetch: { _ in two }, pollInterval: .seconds(100))
        player.start(host: try host())
        await waitUntil { playingID(player) == "1" }
        player.advanceNow()
        #expect(playingID(player) == "2")
        player.stop()

        let one = libraryResponse([item("solo")], durationMs: 100_000)
        let lone = RotationPlayer(fetch: { _ in one }, pollInterval: .seconds(100))
        lone.start(host: try host())
        await waitUntil { playingID(lone) == "solo" }
        lone.advanceNow()
        #expect(playingID(lone) == "solo")
        lone.stop()
    }
}

// The web view's box on the stage (display.css .layer.aspect / .layer.crop).
@Suite struct ConnectedLayoutTests {
    private func piece(aspect: String? = nil, crop: Double? = nil, fit: Fit = .fit) -> DisplayItem {
        DisplayItem(id: "x", kind: .connected, format: nil, fit: fit, collection: "c", crop: crop, aspect: aspect)
    }
    private func expectEqual(_ a: CGSize, _ b: CGSize) {
        #expect(abs(a.width - b.width) < 0.01 && abs(a.height - b.height) < 0.01, "\(a) vs \(b)")
    }

    @Test func readsTheRegistrySpellings() {
        #expect(ConnectedLayout.ratio(from: "1920 / 1080") == 1920.0 / 1080.0)
        #expect(ConnectedLayout.ratio(from: "1 / 1") == 1)
        #expect(ConnectedLayout.ratio(from: "16/9") == 16.0 / 9.0)
        #expect(ConnectedLayout.ratio(from: "1.5") == 1.5)
        #expect(ConnectedLayout.ratio(from: "wide") == nil)
        #expect(ConnectedLayout.ratio(from: "3 / 0") == nil)
    }

    @Test func noDeclarationFillsTheStage() {
        expectEqual(ConnectedLayout.box(for: piece(), in: CGSize(width: 1194, height: 834)), CGSize(width: 1194, height: 834))
    }

    @Test func aspectIsContainedOnFitAndCoversOnFill() {
        let landscape = CGSize(width: 1194, height: 834)      // iPad, landscape
        let portrait = CGSize(width: 393, height: 852)        // phone, portrait
        // A square piece on a landscape stage: a height-limited square, centered by the caller.
        expectEqual(ConnectedLayout.box(for: piece(aspect: "1 / 1"), in: landscape), CGSize(width: 834, height: 834))
        // The same on a portrait stage: width-limited.
        expectEqual(ConnectedLayout.box(for: piece(aspect: "1 / 1"), in: portrait), CGSize(width: 393, height: 393))
        // 16:9 on the landscape iPad: width-limited.
        expectEqual(ConnectedLayout.box(for: piece(aspect: "16 / 9"), in: landscape), CGSize(width: 1194, height: 1194.0 * 9 / 16))
        // Fill: the smallest box of that ratio that covers the stage.
        expectEqual(ConnectedLayout.box(for: piece(aspect: "1 / 1", fit: .fill), in: landscape), CGSize(width: 1194, height: 1194))
        expectEqual(ConnectedLayout.box(for: piece(aspect: "3 / 2", fit: .fill), in: portrait), CGSize(width: 852 * 1.5, height: 852))
    }

    @Test func cropOversizesTheLayer() {
        // send/receive: the art fills the middle 60%, so the layer is 1/0.6 of the stage.
        expectEqual(ConnectedLayout.box(for: piece(crop: 0.6), in: CGSize(width: 600, height: 600)), CGSize(width: 1000, height: 1000))
        // An out-of-range crop is ignored, as in display.js.
        expectEqual(ConnectedLayout.box(for: piece(crop: 1), in: CGSize(width: 600, height: 600)), CGSize(width: 600, height: 600))
    }
}

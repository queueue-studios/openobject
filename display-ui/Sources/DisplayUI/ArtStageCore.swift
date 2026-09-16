import SwiftUI
import UIKit
import DisplayCore
import os

// The zero-chrome art stage, shared by the tvOS and iPad apps (TVOS-APP-PLAN §7). It observes the
// RotationPlayer's screen and renders it: a `.playing` piece is loaded through the MediaPipeline and
// crossfaded in over black (the outgoing piece holds until the incoming is decoded, so there is no
// black gap between pieces); before the Host first answers it shows the Connecting mark, an empty
// rotation shows the splash, and sleep the dimmed drifting mark. This is the native equivalent of
// player/public/display.js's stage.
//
// It owns NO input. Each app wraps ArtStageCore and adds its own way out of the stage (tvOS the Siri
// Remote Menu button, iPad a touch gesture), so the shared crossfade / audio / state logic lives in
// exactly one place while the exit affordance stays per-platform.
//
// Connected pieces (HANDOFF §17, 2026-09-16): the stage renders none itself. An app that can run them (the
// iOS app, in a web view) injects a `connectedLayer` builder; the stage then places the layer with the
// frame's crop/aspect geometry, loads it hidden, crossfades it in only when the layer reports ready, tells
// the player the piece is on screen so its duration counts visible time, and tears the outgoing layer down
// once the fade has settled so one web view is alive in steady state. tvOS passes no builder, and its
// filter never hands the stage a Connected piece anyway.
//
// One deliberate difference from display.js: no 30 s reveal backstop. The frame needs one because it arms
// the next advance from the reveal, so a bundle that never reports ready would wedge its rotation; here the
// player arms the advance from the pick and merely re-arms it at the reveal, so nothing can wedge, and a
// backstop would only ever crossfade to a layer that has not painted (measured: a black stage for the rest
// of a slow bundle's generate). The outgoing piece holds until the incoming one is genuinely ready (§7).
public struct ArtStageCore: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool
    let connectedLayer: ConnectedLayerBuilder?

    public init(player: RotationPlayer, host: Host, pipeline: MediaPipeline, muted: Bool,
                connectedLayer: ConnectedLayerBuilder? = nil) {
        self.player = player
        self.host = host
        self.pipeline = pipeline
        self.muted = muted
        self.connectedLayer = connectedLayer
    }

    @Environment(\.scenePhase) private var scenePhase
    @State private var shownID: String?
    @State private var shownMedia: RenderableMedia?
    @State private var shownFit: Fit = .fit
    // One audio owner across crossfades: the stage silences the outgoing video the instant the next piece
    // takes over, so its sound never bleeds through the fade (§10).
    @State private var audioBus = AudioBus()
    // The Connected layers on the stage: at most one visible, plus one loading hidden behind it (the two
    // layers of display.js). Keyed by the piece's id plus its URL signature, so a control-panel change to a
    // piece on screen loads it afresh and crossfades, exactly as the frame does.
    @State private var webLayers: [WebLayer] = []
    // One line per stage transition, persisted, so a device run can read how many Connected layers were
    // alive at any moment alongside the web layer's own load/unload lines (same subsystem).
    private static let log = Logger(subsystem: "io.openobject.app", category: "stage")

    private struct WebLayer: Identifiable {
        let id: String
        let item: DisplayItem
        var visible: Bool
        let startedAt: ContinuousClock.Instant
    }

    public var body: some View {
        GeometryReader { geo in
            // The wordmark on the text states is 46% of the smaller stage dimension (vmin), matching the
            // web display's 46vmin and the frame; sized to the actual stage so it reads right from an
            // iPhone up to the TV, instead of a fixed point size that overflows a phone.
            let markSize = 0.46 * min(geo.size.width, geo.size.height)
            ZStack {
                Color.black

                // Connecting / idle / sleep marks sit BEHIND the art so a piece crossfades in over them and
                // fades out to reveal them, never flashing bare black (display.js hides the idle mark as the
                // piece fades in, not before).
                stateMark(markSize: markSize)

                // The current art (persisted across the async load of the next piece, so the crossfade has
                // something to fade FROM). Keyed by id so a new piece opacity-crossfades in.
                if let media = shownMedia, let id = shownID {
                    MediaView(media: media, fit: shownFit, muted: muted, audioBus: audioBus)
                        .id(id)
                        .transition(.opacity)
                }

                // Connected layers, each given the frame's crop/aspect box (ConnectedLayout) and clipped to
                // the stage; hidden until ready, then opacity-crossfaded like everything else.
                if let connectedLayer {
                    ForEach(webLayers) { layer in
                        let box = ConnectedLayout.box(for: layer.item, in: geo.size)
                        connectedLayer(ConnectedLayerRequest(
                            item: layer.item, host: host, muted: muted,
                            onReady: { revealWebLayer(layer.id) },
                            onFailed: { webLayerFailed(layer.id) }))
                            .frame(width: box.width, height: box.height)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            .opacity(layer.visible ? 1 : 0)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task(id: currentItemKey) { await syncStage() }
        // Keep the OS screensaver from interrupting the art while the stage is up (§14: idle timer). A
        // playing video defeats it on its own, but stills and animations do not, so hold it off here.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        // Re-assert idle-defeat when the app returns to the foreground: iOS resets isIdleTimerDisabled to
        // false whenever the app backgrounds, and .onAppear does NOT fire again on foreground, so without
        // this the stage would stop defeating auto-lock after any background/foreground cycle.
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }

    // The non-art background for right now (§13): the Connecting mark until the Host first answers, then
    // the branded splash when the rotation has nothing renderable, or the dimmed sleep mark. While a piece
    // is playing this is empty, since the art covers the stage.
    @ViewBuilder private func stateMark(markSize: CGFloat) -> some View {
        if !player.hasConnected {
            ConnectingView(name: host.name, markSize: markSize)
        } else {
            switch player.screen {
            case .idle:      IdleSplashView(address: controlPanelAddress, markSize: markSize)
            case .sleeping:  SleepView(markSize: markSize)
            case .playing:   EmptyView()
            }
        }
    }

    // What identifies the piece to show: its id, plus for a Connected piece everything that reaches its
    // URL, so a live control change reloads it in place (display.js's connected `sig`).
    private var currentItemKey: String? {
        if case let .playing(item) = player.screen { return Self.key(for: item) }
        return nil
    }

    private static func key(for item: DisplayItem) -> String {
        item.kind == .connected ? "\(item.id)|" + ConnectedURL.signature(for: item) : item.id
    }

    // The Host's address, shown on the idle screen so the owner knows where to add art (§13).
    private var controlPanelAddress: String {
        let comps = URLComponents(url: host.baseURL, resolvingAgainstBaseURL: false)
        guard let name = comps?.host else { return host.baseURL.absoluteString }
        if let port = comps?.port, port != 80 { return "\(name):\(port)" }
        return name
    }

    // Load the current piece's media and crossfade it in; clear the stage when idle/asleep. Either way,
    // cut the outgoing piece's audio at the swap (not when its fade ends) so it never plays over the next.
    private func syncStage() async {
        guard case let .playing(item) = player.screen else {
            audioBus.silenceCurrent()
            withAnimation(.easeInOut(duration: 0.6)) { shownMedia = nil; shownID = nil; hideWebLayers() }
            scheduleWebCleanup()
            return
        }
        if item.kind == .connected {
            // Rendered by the injected layer (the iOS web view): it loads hidden and reveals itself via
            // onReady. Without a builder there is nothing to show; the filter should never let this happen.
            guard connectedLayer != nil else { return }
            startWebLayer(for: item)
            return
        }
        guard let media = try? await pipeline.load(item, from: host) else {
            Self.log.error("native piece \(item.id, privacy: .public) failed to load; holding the current piece")
            return
        }
        audioBus.silenceCurrent()
        withAnimation(.easeInOut(duration: 0.6)) {
            shownMedia = media
            shownID = item.id
            shownFit = item.fit
            hideWebLayers()
        }
        Self.log.log("show native \(item.id, privacy: .public); web layers alive \(self.webLayers.count)")
        scheduleWebCleanup()
    }

    // MARK: - Connected layers

    // Add the piece's layer hidden (the loading half of the crossfade). It stays hidden until it reports
    // ready; if it never does, the rotation's own timer moves on and the cleanup drops it.
    private func startWebLayer(for item: DisplayItem) {
        let key = Self.key(for: item)
        guard !webLayers.contains(where: { $0.id == key }) else { return }
        webLayers.append(WebLayer(id: key, item: item, visible: false, startedAt: .now))
        Self.log.log("start web \(item.id, privacy: .public); web layers alive \(self.webLayers.count)")
    }

    // The layer is ready: crossfade it in over whatever is showing, silence an outgoing video, and start
    // the piece's duration from now (HANDOFF §7: visible time). A ready from a layer the rotation has since
    // moved past is dropped with its layer.
    private func revealWebLayer(_ key: String) {
        guard let index = webLayers.firstIndex(where: { $0.id == key }), !webLayers[index].visible else { return }
        guard key == currentItemKey else { webLayers.remove(at: index); return }
        audioBus.silenceCurrent()
        withAnimation(.easeInOut(duration: 0.6)) {
            shownMedia = nil
            shownID = nil
            for i in webLayers.indices { webLayers[i].visible = (i == index) }
        }
        player.pieceRevealed(id: webLayers[index].item.id)
        Self.log.log("show web \(self.webLayers[index].item.id, privacy: .public); web layers alive \(self.webLayers.count)")
        scheduleWebCleanup()
    }

    // The layer's web content process has died twice (its renderer reloaded it once already): the piece
    // cannot paint, so it gives up its turn rather than holding a black stage, after a short floor so an
    // instant death never makes the rotation flicker. Only if it is still the piece on screen.
    private func webLayerFailed(_ key: String) {
        guard let layer = webLayers.first(where: { $0.id == key }) else { return }
        Task {
            let floor = layer.startedAt.advanced(by: .seconds(2))
            if ContinuousClock.now < floor { try? await Task.sleep(until: floor) }
            guard key == currentItemKey else { return }
            player.advanceNow()
        }
    }

    private func hideWebLayers() {
        for i in webLayers.indices { webLayers[i].visible = false }
    }

    // Once a crossfade has settled, drop every hidden layer except one still loading for the current piece
    // (display.js freeHiddenLayer): the outgoing web view stops rendering and releases its memory.
    private func scheduleWebCleanup() {
        Task {
            try? await Task.sleep(for: .milliseconds(750))
            let current = currentItemKey
            let before = webLayers.count
            webLayers.removeAll { !$0.visible && $0.id != current }
            if before != webLayers.count {
                Self.log.log("cleanup dropped \(before - self.webLayers.count); web layers alive \(self.webLayers.count)")
            }
        }
    }
}

/// What an app's Connected-layer builder receives: the piece and Host to render, the stage's Sound setting,
/// and two callbacks. `onReady` once the piece has painted (the stage crossfades it in); `onFailed` when it
/// cannot (the stage moves on). The stage sizes and clips the returned view; the builder just renders.
public struct ConnectedLayerRequest {
    public let item: DisplayItem
    public let host: Host
    public let muted: Bool
    public let onReady: () -> Void
    public let onFailed: () -> Void
}

/// An app-supplied renderer for Connected pieces (the iOS app's web view). Nil on tvOS.
public typealias ConnectedLayerBuilder = (ConnectedLayerRequest) -> AnyView

// The branded wordmark, sized to the stage (46% of its smaller dimension) so it reads at the same vertical
// proportion from a phone to the TV, matching the web display's 46vmin idle/sleep mark (§13, Branding).
// The image asset "OpenObjectLogo" is provided by each app's asset catalog (resolved from the main bundle).
private struct StageMark: View {
    let size: CGFloat

    var body: some View {
        Image("OpenObjectLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(.white)
            .accessibilityLabel("OpenObject")
    }
}

// Connecting (§13): active and brief, shown from choosing a Host until its first poll answers, phrased as
// progress so the opening beat never reads as empty or broken.
struct ConnectingView: View {
    let name: String
    let markSize: CGFloat

    var body: some View {
        VStack(spacing: 32) {
            StageMark(size: markSize)
            Text("Connecting to \(name)…")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// Idle / empty state (§13): the branded wordmark plus where to add art, phrased as what will appear
// rather than what is missing. Shown when connected to a Host whose rotation has nothing renderable.
struct IdleSplashView: View {
    let address: String
    let markSize: CGFloat

    var body: some View {
        VStack(spacing: 32) {
            StageMark(size: markSize)
            Text("Add art at \(address)")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// Sleep Hours / Blank (§13): the same wordmark as idle but dimmed to a whisper and text-free, drifting a
// few points on a slow cycle so a static mark can't sit on the panel (anti-burn-in). Mirrors the web
// display's .asleep mark: opacity 0.05, a random +/-6 pt shift every 90s gliding over a 4s ease.
struct SleepView: View {
    let markSize: CGFloat
    @State private var drift: CGSize = .zero

    var body: some View {
        ZStack {
            Color.black
            StageMark(size: markSize)
                .opacity(0.05)
                .offset(drift)
                .animation(.easeInOut(duration: 4), value: drift)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            while !Task.isCancelled {
                drift = CGSize(width: .random(in: -6...6), height: .random(in: -6...6))
                try? await Task.sleep(for: .seconds(90))
            }
        }
    }
}

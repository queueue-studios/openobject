import SwiftUI
import UIKit
import DisplayCore

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
public struct ArtStageCore: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool

    public init(player: RotationPlayer, host: Host, pipeline: MediaPipeline, muted: Bool) {
        self.player = player
        self.host = host
        self.pipeline = pipeline
        self.muted = muted
    }

    @State private var shownID: String?
    @State private var shownMedia: RenderableMedia?
    @State private var shownFit: Fit = .fit
    // One audio owner across crossfades: the stage silences the outgoing video the instant the next piece
    // takes over, so its sound never bleeds through the fade (§10).
    @State private var audioBus = AudioBus()

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
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .task(id: currentItemID) { await syncStage() }
        // Keep the OS screensaver from interrupting the art while the stage is up (§14: idle timer). A
        // playing video defeats it on its own, but stills and animations do not, so hold it off here.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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

    private var currentItemID: String? {
        if case let .playing(item) = player.screen { return item.id }
        return nil
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
            withAnimation(.easeInOut(duration: 0.6)) { shownMedia = nil; shownID = nil }
            return
        }
        guard let media = try? await pipeline.load(item, from: host) else { return }
        audioBus.silenceCurrent()
        withAnimation(.easeInOut(duration: 0.6)) {
            shownMedia = media
            shownID = item.id
            shownFit = item.fit
        }
    }
}

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

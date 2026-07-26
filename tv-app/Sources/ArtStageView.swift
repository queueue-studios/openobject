import SwiftUI
import UIKit
import DisplayCore

// The zero-chrome art stage (§6): it observes the RotationPlayer's screen and renders it. A `.playing`
// piece is loaded through the MediaPipeline and crossfaded in over black (the outgoing piece holds
// until the incoming is decoded, so there is no black gap between pieces); idle shows the splash, sleep
// the dimmed screen. This is the tvOS equivalent of player/public/display.js's stage.
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool

    @State private var shownID: String?
    @State private var shownMedia: RenderableMedia?
    @State private var shownFit: Fit = .fit

    var body: some View {
        ZStack {
            Color.black

            // The current art (persisted across the async load of the next piece, so the crossfade has
            // something to fade FROM). Keyed by id so a new piece opacity-crossfades in.
            if let media = shownMedia, let id = shownID {
                MediaView(media: media, fit: shownFit, muted: muted)
                    .id(id)
                    .transition(.opacity)
            }

            switch player.screen {
            case .idle:      IdleSplashView(address: controlPanelAddress)
            case .sleeping:  SleepView()
            case .playing:   EmptyView()
            }
        }
        .ignoresSafeArea()
        .task(id: currentItemID) { await syncStage() }
        // Keep the tvOS screensaver from interrupting the art while the stage is up (§14: idle timer). A
        // playing video defeats it on its own, but stills and animations do not, so hold it off here.
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
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

    // Load the current piece's media and crossfade it in; clear the stage when idle/asleep.
    private func syncStage() async {
        guard case let .playing(item) = player.screen else {
            withAnimation(.easeInOut(duration: 0.6)) { shownMedia = nil; shownID = nil }
            return
        }
        guard let media = try? await pipeline.load(item, from: host) else { return }
        withAnimation(.easeInOut(duration: 0.6)) {
            shownMedia = media
            shownID = item.id
            shownFit = item.fit
        }
    }
}

// Idle / empty state (§13): the branded wordmark plus where to add art, phrased as what will appear
// rather than what is missing. Shown when connected to a Host whose rotation has nothing renderable.
struct IdleSplashView: View {
    let address: String

    var body: some View {
        VStack(spacing: 32) {
            Image("OpenObjectLogo")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 360, height: 360)
                .foregroundStyle(.white)
                .accessibilityLabel("OpenObject")
            Text("Add art at \(address)")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

// Sleep Hours / Blank (§13): a dark, text-free screen. C5 adds the dimmed mark and anti-burn-in drift.
struct SleepView: View {
    var body: some View {
        Color.black.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

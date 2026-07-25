import SwiftUI
import DisplayCore

// The zero-chrome art stage (§6): it observes the RotationPlayer's screen and renders it. A `.playing`
// piece is loaded through the MediaPipeline and crossfaded in over black (the outgoing piece holds
// until the incoming is decoded, so there is no black gap between pieces); idle shows the splash, sleep
// the dimmed screen. This is the tvOS equivalent of player/public/display.js's stage.
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline

    @State private var shownID: String?
    @State private var shownMedia: RenderableMedia?
    @State private var shownFit: Fit = .fit

    var body: some View {
        ZStack {
            Color.black

            // The current art (persisted across the async load of the next piece, so the crossfade has
            // something to fade FROM). Keyed by id so a new piece opacity-crossfades in.
            if let media = shownMedia, let id = shownID {
                MediaView(media: media, fit: shownFit)
                    .id(id)
                    .transition(.opacity)
            }

            switch player.screen {
            case .idle:      IdleSplashView()
            case .sleeping:  SleepView()
            case .playing:   EmptyView()
            }
        }
        .ignoresSafeArea()
        .task(id: currentItemID) { await syncStage() }
    }

    private var currentItemID: String? {
        if case let .playing(item) = player.screen { return item.id }
        return nil
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

// Idle / empty state: the branded mark comes in Phase D; for now a plain mark + the web display's hint.
struct IdleSplashView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("OpenObject")
                .font(.system(size: 80, weight: .semibold))
                .foregroundStyle(.white)
            Text("Add art from the control panel")
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

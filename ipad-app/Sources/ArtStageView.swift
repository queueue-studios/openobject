import SwiftUI
import DisplayCore
import DisplayUI

// The iPad art stage: the shared ArtStageCore (DisplayUI) rendering the rotation, plus the iOS-specific
// chrome hiding (status bar + home indicator) and the touch way back to the picker. The stage is
// zero-chrome by default; a tap reveals a "Hosts" control, and tapping THAT returns to the picker.
// The reveal is itself the speedbump: a stray tap on the art only shows the control (tap the art again to
// dismiss it) and never navigates, so leaving the piece takes a deliberate second tap on the control.
// ArtStageCore owns the crossfade, audio, idle/sleep marks, and screensaver defeat (shared with tvOS).
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool
    let onExit: () -> Void

    @State private var showControls = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArtStageCore(player: player, host: host, pipeline: pipeline, muted: muted)
                .ignoresSafeArea()

            // Full-stage tap catcher (near-transparent fill, contentShape-reliable): a tap on the art
            // toggles the control, over stills and video alike. This reveal is the speedbump — a stray tap
            // only shows the control, it never leaves the art.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                }

            // The revealed control (respects the safe area so it clears the notch/camera). A deliberate tap
            // here returns to the picker.
            if showControls {
                Button {
                    onExit()
                } label: {
                    Label("Hosts", systemImage: "chevron.backward")
                        .font(.headline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding()
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
    }
}

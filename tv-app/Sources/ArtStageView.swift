import SwiftUI
import UIKit
import DisplayCore
import DisplayUI

// The tvOS art stage: the shared ArtStageCore (DisplayUI) plus the one tvOS-specific concern, exiting
// back to the picker on the Siri Remote's Menu/Back button. ArtStageCore renders no focusable content,
// so the stage must be focusable itself to receive the exit command; the focus effect is disabled so the
// art stays zero-chrome (§14, §15). Everything the stage draws (crossfade, audio, idle/sleep marks,
// screensaver defeat) lives in ArtStageCore and is shared with the iPad app, which wraps the same core
// with a touch exit instead.
//
// While the connected Host flies its Retro Arcade flag (HANDOFF §20), the stage shows the native demo
// in place of the art, so the Control Panel's hidden code flips the frame, the Mac, the iPad, and this
// Apple TV together; Return to Art restores the rotation within a poll. Back exits in both modes.
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool
    let onExit: () -> Void

    @FocusState private var stageFocused: Bool

    var body: some View {
        Group {
            if player.hostArcade {
                ArcadeStage()
            } else {
                ArtStageCore(player: player, host: host, pipeline: pipeline, muted: muted)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .focused($stageFocused)
        .onExitCommand { onExit() }
        .onAppear { stageFocused = true }
        // ArtStageCore clears the screensaver defeat in its onDisappear, whose order against the arcade's
        // incoming onAppear is undefined (the same race the iPad hit), so re-assert it one tick after the
        // swap in either direction; the stage is on screen throughout.
        .onChange(of: player.hostArcade) { _, _ in
            stageFocused = true
            DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
        }
    }
}

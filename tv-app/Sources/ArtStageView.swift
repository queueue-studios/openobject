import SwiftUI
import DisplayCore
import DisplayUI

// The tvOS art stage: the shared ArtStageCore (DisplayUI) plus the one tvOS-specific concern, exiting
// back to the picker on the Siri Remote's Menu/Back button. ArtStageCore renders no focusable content,
// so the stage must be focusable itself to receive the exit command; the focus effect is disabled so the
// art stays zero-chrome (§14, §15). Everything the stage draws (crossfade, audio, idle/sleep marks,
// screensaver defeat) lives in ArtStageCore and is shared with the iPad app, which wraps the same core
// with a touch exit instead.
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool
    let onExit: () -> Void

    @FocusState private var stageFocused: Bool

    var body: some View {
        ArtStageCore(player: player, host: host, pipeline: pipeline, muted: muted)
            .focusable()
            .focusEffectDisabled()
            .focused($stageFocused)
            .onExitCommand { onExit() }
            .onAppear { stageFocused = true }
    }
}

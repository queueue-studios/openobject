import SwiftUI
import DisplayCore
import DisplayUI

// The iPad art stage: the shared ArtStageCore (DisplayUI) plus the iOS-specific chrome hiding so art
// reaches the physical edges (status bar + home indicator auto-hidden). The stage follows the device
// orientation. ArtStageCore itself owns the crossfade, audio, idle/sleep marks, and screensaver defeat,
// shared with the tvOS app; the touch exit back to the picker is added in G4.
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool

    var body: some View {
        ArtStageCore(player: player, host: host, pipeline: pipeline, muted: muted)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)   // auto-hide the home indicator on the art stage
    }
}

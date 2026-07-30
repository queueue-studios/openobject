import SwiftUI
import DisplayCore

// Root of the iPad app. It shows the Host picker until a Host is chosen (or one was remembered from a
// previous launch), then the zero-chrome art stage for that Host. Mirrors the tvOS RootView. The picker
// is landscape-locked in G3b; the stage's touch exit back to the picker arrives in G4 (so for now the app
// opens straight to art whenever a Host is remembered).
struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            switch model.route {
            case .picker:
                HostPickerView(model: model)
            case .display(let host):
                ArtStageView(player: model.player, host: host, pipeline: model.pipeline,
                             muted: !model.soundOn, onExit: { model.showPicker() })
            }
        }
        .ignoresSafeArea()
    }
}

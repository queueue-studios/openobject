import SwiftUI
import DisplayCore

// Root of the tvOS app. It shows the Host picker until a Host is chosen (or one was remembered from a
// previous launch), then the zero-chrome art stage for that Host. C4 replaced C3's OO_HOST stopgap with
// this real flow: discovery + manual entry + a remembered default Host, all coordinated by AppModel.
struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            switch model.route {
            case .picker:
                HostPickerView(model: model)
            case .display(let host):
                ArtStageView(player: model.player, host: host, pipeline: model.pipeline)
            }
        }
        .ignoresSafeArea()
    }
}

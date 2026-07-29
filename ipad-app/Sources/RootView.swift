import SwiftUI
import DisplayCore

// Root of the iPad app. It shows the Host picker until a Host is chosen (or one was remembered from a
// previous launch), then the zero-chrome art stage for that Host. Mirrors the tvOS RootView. In G2 the
// picker is a placeholder (the real landscape-locked touch picker is G3) and the stage has no touch exit
// yet (G4), so for now the app opens straight to art whenever a Host is remembered, the same stopgap the
// tvOS app used at C3.
struct RootView: View {
    @State private var model = AppModel()

    var body: some View {
        Group {
            switch model.route {
            case .picker:
                PickerPlaceholderView()
            case .display(let host):
                ArtStageView(player: model.player, host: host, pipeline: model.pipeline,
                             muted: !model.soundOn)
            }
        }
        .ignoresSafeArea()
    }
}

// Temporary stand-in for the .picker route until G3 builds the real landscape-locked touch picker.
private struct PickerPlaceholderView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("OpenObjectLogo")
                    .renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 360).foregroundStyle(.white)
                    .accessibilityLabel("OpenObject")
                Text("Host picker (G3)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

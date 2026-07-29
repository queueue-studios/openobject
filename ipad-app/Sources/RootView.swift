import SwiftUI

// G1 scaffold placeholder. It proves the Universal target builds, links the shared DisplayCore and
// DisplayUI packages (compiled as declared dependencies), and renders the shared OpenObjectLogo asset.
// The real flow arrives next: G2 wires the art stage (ArtStageCore from DisplayUI, wrapped with a touch
// exit) and G3 the landscape-locked Host picker, mirroring the tvOS RootView with touch input.
struct RootView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("OpenObjectLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 360)
                    .foregroundStyle(.white)
                    .accessibilityLabel("OpenObject")
                Text("iPad scaffold")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

import SwiftUI
import DisplayCore

// C1 skeleton view: proves the app builds and LINKS DisplayCore. The real screens (Host picker, the
// art stage, the waiting/splash/sleep states, §13) replace this in the later Phase C checkpoints.
struct RootView: View {
    var body: some View {
        Text("OpenObject")
            .font(.system(size: 96, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .onAppear {
                // Touch DisplayCore so the package is actually linked (a build-time proof; removed once
                // the real screens consume the engine).
                _ = CapabilityFilter().canRender(kind: .still, format: .jpeg)
            }
    }
}

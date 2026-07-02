import SwiftUI

// The main window's placeholder content (B1a skeleton). In later checkpoints this becomes the
// app's status/onboarding surface (Host vs Display role, which server, start/stop).
struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("OpenObject")
                .font(.title.weight(.semibold))
            Text("Mac app skeleton (Phase B1a)")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .frame(minWidth: 380, minHeight: 260)
    }
}

#Preview {
    ContentView()
}

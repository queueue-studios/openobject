import SwiftUI
import DisplayCore

// The Host picker (TVOS-APP-PLAN §5, §13): the first screen when no Host is remembered. It lists the
// OpenObject Hosts found on the network and offers manual address entry as a fallback. Plain language, no
// jargon - "your OpenObject", not "Host". Choosing one remembers it and opens its art.
struct HostPickerView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 56) {
                Image("OpenObjectLogo")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 420, height: 420)
                    .foregroundStyle(.white)
                    .accessibilityLabel("OpenObject")

                discoveredHosts

                manualEntry
            }
            .padding(.horizontal, 80)
            .padding(.top, 64)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Pinned to the screen's bottom-right corner (§10), inside the tvOS title-safe margin.
            SoundToggleButton(model: model)
                .padding(.trailing, 90)
                .padding(.bottom, 60)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .onAppear { model.startDiscoveryIfPicking() }
    }

    @ViewBuilder private var discoveredHosts: some View {
        if model.hosts.isEmpty {
            VStack(spacing: 20) {
                if model.scanning {
                    ProgressView().scaleEffect(1.6).tint(.white)
                    Text("Looking for OpenObject on your network…")
                        .font(.title3).foregroundStyle(.secondary)
                } else {
                    Text("No OpenObject found on your network yet.")
                        .font(.title3).foregroundStyle(.secondary)
                    Text("Make sure it's on and on the same Wi-Fi.")
                        .font(.callout).foregroundStyle(.tertiary)
                }
            }
            .frame(height: 200)
        } else {
            VStack(spacing: 16) {
                ForEach(model.hosts) { host in
                    Button { model.select(host) } label: {
                        HStack(spacing: 20) {
                            Image(systemName: "play.tv")
                            Text(host.name).font(.title2).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(width: 1500)
            .frame(minHeight: 200)
        }
    }

    @ViewBuilder private var manualEntry: some View {
        VStack(spacing: 20) {
            Text("Or enter its address")
                .font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 20) {
                TextField("192.168.1.10 or openobject.local", text: $model.manualAddress)
                    .textContentType(.URL)
                    .frame(width: 760)
                Button("Connect") { Task { await model.submitManualEntry() } }
            }
            if let error = model.manualError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }
}

// The app-owned Sound toggle (§10): a bare speaker icon (waves when on, a slash when muted), no button
// chrome. Sticky and default On. A set-once control, so it rests in the secondary gray (matching the
// picker's supporting text) and only comes forward — white and scaled up — when focused with the remote.
// The symbols are the platform-standard audio glyphs; speaker.slash.fill is what the Siri Remote's mute
// button and the system volume HUD use.
private struct SoundToggleButton: View {
    let model: AppModel
    @FocusState private var focused: Bool

    var body: some View {
        Button {
            model.soundOn.toggle()
        } label: {
            Image(systemName: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(focused ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .scaleEffect(focused ? 1.2 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .accessibilityLabel(model.soundOn ? "Sound on" : "Sound off")
    }
}

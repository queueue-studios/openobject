import SwiftUI
import DisplayCore

// The Host picker (TVOS-APP-PLAN §5, §13): the first screen when no Host is remembered. It lists the
// OpenObject Hosts found on the network and offers manual address entry as a fallback. Plain language, no
// jargon - "your OpenObject", not "Host". Choosing one remembers it and opens its art.
struct HostPickerView: View {
    @Bindable var model: AppModel

    // Which host row holds focus. We steer initial focus onto the first row (people read top-down) so the
    // remote's primary action is right there on arrival, instead of tvOS's default of the bottom control.
    @FocusState private var focusedHost: String?
    // Flips true once the owner moves focus themselves; after that we stop steering.
    @State private var ownerTookFocus = false

    var body: some View {
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
        .background(Color.black)
        // The Sound icon rides on its own full-screen layer so it can sit in the physical bottom-right
        // corner without pulling the content (the text field especially) out of the safe area.
        .overlay {
            SoundToggleButton(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, 90)
                .padding(.bottom, 60)
                .ignoresSafeArea()
        }
        .onAppear {
            model.startDiscoveryIfPicking()
            pinFocusToFirstHost()
        }
        // Hosts arrive (and re-sort) asynchronously over Bonjour, so keep focus on whichever row is
        // currently first until the owner moves it themselves - otherwise a late host that sorts ahead
        // leaves focus stranded on the wrong row (as it did on the second row before this).
        .onChange(of: model.hosts) { _, _ in pinFocusToFirstHost() }
        .onChange(of: focusedHost) { _, newValue in
            // Any focus resting somewhere other than the current first row is the owner navigating (a
            // lower row, or the address field, which clears focusedHost). Once that happens, stop steering.
            if newValue != model.hosts.first?.id { ownerTookFocus = true }
        }
    }

    // Keep initial focus on the first host row while the list is still settling, and only until the owner
    // has taken focus somewhere themselves (so a late-arriving host never yanks the cursor from under them).
    private func pinFocusToFirstHost() {
        guard !ownerTookFocus, let first = model.hosts.first else { return }
        focusedHost = first.id
    }

    @ViewBuilder private var discoveredHosts: some View {
        if model.hosts.isEmpty {
            VStack(spacing: 20) {
                if model.scanning {
                    ProgressView().scaleEffect(1.6).tint(.white)
                    Text("Looking for Hosts on your network…")
                        .font(.title3).foregroundStyle(.secondary)
                } else {
                    Text("No Hosts found on your network.")
                        .font(.title3).foregroundStyle(.secondary)
                    Text("Your Apple TV is ready to connect. Once an OpenObject Host is running on your network, it will appear here automatically.")
                        .font(.callout).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1100)
                }
            }
            .frame(minHeight: 200)
        } else {
            VStack(spacing: 24) {
                Text("Choose a Host")
                    .font(.headline).foregroundStyle(.secondary)
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
                        .focused($focusedHost, equals: host.id)
                    }
                }
                .frame(width: 1500)
            }
            .frame(minHeight: 200)
        }
    }

    @ViewBuilder private var manualEntry: some View {
        VStack(spacing: 20) {
            Text(model.hosts.isEmpty ? "Know a Host's address?" : "Or enter its address")
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
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(focused ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .scaleEffect(focused ? 1.2 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }
        .buttonStyle(.plain)
        .focused($focused)
        .accessibilityLabel(model.soundOn ? "Sound on" : "Sound off")
    }
}

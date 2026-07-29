import SwiftUI
import DisplayCore

// The touch Host picker (TVOS-APP-PLAN §5, §13): the first screen when no Host is remembered. It lists
// the OpenObject Hosts found on the network and offers manual address entry as a fallback. Modeled on the
// tvOS picker's layout (wordmark, host list, address field, Sound) but driven by touch instead of the
// focus engine: rows are tapped, the address field uses the software keyboard. Plain language, no jargon.
// Both this screen and the stage follow the device orientation (no landscape lock).
struct HostPickerView: View {
    @Bindable var model: AppModel
    @FocusState private var addressFocused: Bool

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Image("OpenObjectLogo")
                    .renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 260)
                    .foregroundStyle(.white)
                    .accessibilityLabel("OpenObject")

                discoveredHosts
                manualEntry
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 40)

            // Sound control, bottom-right (mirrors the tvOS placement): the device's own volume is the
            // loudness control above it; this toggle just decides whether the art makes noise at all.
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    SoundToggleButton(model: model)
                }
            }
            .padding(28)
        }
        .onAppear { model.startDiscoveryIfPicking() }
    }

    @ViewBuilder private var discoveredHosts: some View {
        if model.hosts.isEmpty {
            VStack(spacing: 14) {
                if model.scanning {
                    ProgressView().tint(.white).scaleEffect(1.2)
                    Text("Looking for Hosts on your network…")
                        .font(.title3).foregroundStyle(.secondary)
                } else {
                    Text("No Hosts found on your network.")
                        .font(.title3).foregroundStyle(.secondary)
                    Text("Once an OpenObject Host is running on your network, it will appear here automatically.")
                        .font(.callout).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(minHeight: 120)
        } else {
            VStack(spacing: 16) {
                Text("Choose a Host").font(.headline).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    ForEach(model.hosts) { host in
                        Button { model.select(host) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "play.tv")
                                Text(host.name).font(.title3).fontWeight(.medium).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 16).padding(.horizontal, 20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                    }
                }
            }
            .frame(minHeight: 120)
        }
    }

    @ViewBuilder private var manualEntry: some View {
        VStack(spacing: 14) {
            Text(model.hosts.isEmpty ? "Know a Host's address?" : "Or enter its address")
                .font(.headline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                TextField("192.168.1.10 or openobject.local", text: $model.manualAddress)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($addressFocused)
                    .frame(maxWidth: 360)
                    .onSubmit { submit() }
                Button("Connect") { submit() }
                    .buttonStyle(.borderedProminent)
            }
            if let error = model.manualError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        addressFocused = false
        Task { await model.submitManualEntry() }
    }
}

// The app-owned Sound toggle (§10): a bare speaker icon (waves when on, a slash when muted). Sticky and
// default On; a set-once control, so it rests in secondary gray. The device's own volume is the loudness
// control above it; this only decides whether the art makes noise at all.
private struct SoundToggleButton: View {
    let model: AppModel

    var body: some View {
        Button {
            model.soundOn.toggle()
        } label: {
            Image(systemName: model.soundOn ? "speaker.wave.2.fill" : "speaker.slash.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(model.soundOn ? "Sound on" : "Sound off")
    }
}

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
    @Environment(\.scenePhase) private var scenePhase

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
        // First launch: the Local Network permission is granted while a browse is already in flight, which
        // the in-flight browser does not pick up. When the app becomes active again (right after that
        // permission alert is dismissed) with nothing found yet, restart browsing so the Host appears
        // without a manual relaunch.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && model.hosts.isEmpty { model.rescan() }
        }
    }

    @ViewBuilder private var discoveredHosts: some View {
        if model.hosts.isEmpty {
            emptyState
        } else {
            VStack(spacing: 16) {
                Text("Choose a Host").font(.headline).foregroundStyle(.secondary)
                VStack(spacing: 12) {
                    ForEach(model.hosts) { host in
                        PickerRow(icon: "play.tv", title: host.name) { model.select(host) }
                    }
                }
            }
            .frame(minHeight: 120)
        }
    }

    // The empty state (§13): honest that no Host was found. When the public Gallery actually answers
    // (probe-gated), it offers the OpenObject Gallery so the screen is never a dead end. The Gallery row is
    // styled exactly like a discovered-Host row (same size/area); its name plus the framed-picture icon say
    // what it is, so no instructional copy is needed. When the Gallery is unreachable (or still being
    // probed) the plain "it will appear here automatically" reassurance stands in its place.
    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 14) {
            if model.scanning {
                ProgressView().tint(.white).scaleEffect(1.2)
                Text("Looking for Hosts on your network…")
                    .font(.title3).foregroundStyle(.secondary)
            } else {
                Text("No Hosts found on your network.")
                    .font(.title3).foregroundStyle(.secondary)
                if model.galleryReachable == true {
                    PickerRow(icon: "photo.artframe", title: "OpenObject Gallery") { model.connectToGallery() }
                } else {
                    Text("Once an OpenObject Host is running on your network, it will appear here automatically.")
                        .font(.callout).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(minHeight: 120)
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

// A tappable row in the picker: an SF Symbol + a title in a rounded fill, full-width. Shared by the
// discovered-Host rows (play.tv) and the empty-state OpenObject Gallery row (photo.artframe) so both read
// at the same size and area; only the icon and label differ (§13).
private struct PickerRow: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                Text(title).font(.title3).fontWeight(.medium).lineLimit(1)
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

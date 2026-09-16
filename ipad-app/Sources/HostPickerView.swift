import SwiftUI
import UIKit
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
                    localCopyRow
                }
            }
            .frame(minHeight: 120)
        }
    }

    // The local copy (HANDOFF §17): the held Host's own row, tagged "Local copy", shown only while that Host is
    // not on the network. Its glyph is this device, since that is where the art is (a live Host keeps play.tv).
    // It sits after any live Hosts and before the Demo Gallery. Deliberately not a generic "cached gallery"
    // pseudo-Host: the row says exactly what is true, the Host is not here but its art is.
    @ViewBuilder private var localCopyRow: some View {
        if let host = model.localCopyRow {
            PickerRow(icon: deviceIcon, title: host.name, detail: "Local copy") { model.select(host) }
        }
    }

    private var deviceIcon: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    // The empty state (§13): WAITING, not failed. The shipped build had drifted to a bare negative ("No
    // Hosts found on your network.") which, with the Gallery row beside it, an App Store reviewer read as
    // a failure with an unexplained button (§17, E23). The headline is also the explanation, so nothing is
    // repeated beneath it. It drops the "OpenObject" §13 wrote into it (Matt, 2026-09-01): the wordmark sits
    // directly above, and the scanning line one second earlier says plain "Hosts", so the brand here was
    // both redundant and inconsistent. §13 was corrected to match rather than left to drift again. When the public Gallery answers its probe it
    // is offered as a row styled exactly like a discovered-Host row (same size/area); its name plus the
    // framed-picture icon say what it is, so no instructional copy is needed. Unreachable (or still
    // probing) shows the one sentence the headline does not already cover: that this device itself is fine.
    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 14) {
            if model.scanning {
                ProgressView().tint(.white).scaleEffect(1.2)
                Text("Looking for Hosts on your network…")
                    .font(.title3).foregroundStyle(.secondary)
                localCopyRow
            } else {
                Text("Hosts on your network will appear here.")
                    .font(.title3).foregroundStyle(.secondary)
                localCopyRow
                if model.galleryReachable == true {
                    PickerRow(icon: "photo.artframe", title: Host.gallery.name, iconFont: .title3) { model.connectToGallery() }
                } else if model.localCopyRow == nil {
                    Text("Your \(deviceName) is ready to connect.")
                        .font(.callout).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(minHeight: 120)
    }

    // tvOS names the device in this line already; this app is Universal, so the name comes from the idiom
    // rather than being hard-coded (saying "Your iPad" on an iPhone would be its own small lie).
    private var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    // Connect means nothing with nothing typed, so it is DISABLED rather than labelled with a hint (the
    // house rule is to fix behavior to match expectation, not to explain it). Tapping it empty used to put
    // a red error under the field, which the App Review reviewer read as a required login that had failed
    // (§17, E23). The keyboard's Go key is guarded in submit() for the same reason; model.manualError stays
    // as a defensive guard, but the UI can no longer reach its empty case.
    //
    // It is also disabled, and shows a spinner in place of its label, while a probe is in flight (E24): the
    // shipped build kept it enabled and silent for up to a minute, which on a real iPhone read as a button
    // that did nothing. The label is kept at its own width underneath so the button does not change size.
    private var addressIsEmpty: Bool {
        model.manualAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                Button {
                    submit()
                } label: {
                    Text("Connect")
                        .opacity(model.connecting ? 0 : 1)
                        .overlay { if model.connecting { ProgressView().tint(.white) } }
                }
                .buttonStyle(.borderedProminent)
                .disabled(addressIsEmpty || model.connecting)
            }
            if let error = model.manualError {
                Text(error).font(.callout).foregroundStyle(.red)
            }
        }
    }

    private func submit() {
        guard !addressIsEmpty, !model.connecting else { return }
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
    // Per-icon size: different SF Symbols read at different visual sizes at the same point size, so a glyph
    // with more built-in padding (photo.artframe) is bumped to match a fuller one (play.tv). Default keeps
    // the host row's icon unchanged.
    var iconFont: Font = .body
    // A quiet right-aligned tag ("Local copy"); nil for a plain row.
    var detail: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(iconFont)
                // Scale down before truncating. "OpenObject Demo Gallery" is 6 characters longer than the
                // name it replaced and overflows a single line on iPhone, and an ellipsis there would eat
                // the word "Demo" - the one word the rename exists to show. Only engages when needed, so
                // the iPad and every shorter Host name are untouched.
                Text(title).font(.title3).fontWeight(.medium).lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
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

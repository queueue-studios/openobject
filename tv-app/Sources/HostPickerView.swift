import SwiftUI
import DisplayCore

// The Host picker (TVOS-APP-PLAN §5, §13): the first screen when no Host is remembered. It lists the
// OpenObject Hosts found on the network and offers manual address entry as a fallback. Plain language, no
// jargon - "your OpenObject", not "Host". Choosing one remembers it and opens its art.
struct HostPickerView: View {
    @Bindable var model: AppModel

    @Environment(\.scenePhase) private var scenePhase

    // Which host row holds focus. We steer initial focus onto the first row (people read top-down) so the
    // remote's primary action is right there on arrival, instead of tvOS's default of the bottom control.
    @FocusState private var focusedHost: String?
    // Flips true once the owner moves focus themselves; after that we stop steering.
    @State private var ownerTookFocus = false

    var body: some View {
        VStack(spacing: 0) {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .focusSection()   // the hosts + address field are one focus section

            // The Sound control lives in a full-width bottom row that is its OWN focus section and a real
            // sibling of the content (not an overlay), so a press down from the hosts or the address field
            // lands on it. tvOS focus moves only up/down/left/right, and the earlier corner overlay sat
            // diagonally from every control on a separate layer, so no direction ever reached it.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                SoundToggleButton(model: model)
            }
            .focusSection()
        }
        .padding(.horizontal, 80)
        .padding(.top, 64)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.black)
        .onAppear {
            model.startDiscoveryIfPicking()
            pinInitialFocus()
        }
        // Returning to the app reopens the remembered Host's art, and otherwise restarts browsing so the
        // picker is never a stale empty list (an Apple TV that slept, or a browse that began before the
        // Local Network grant, used to leave it empty with no way to retry).
        //
        // Gated on the previous phase so it is a real return from the background, not any other pass
        // through .active: arriving here from the art stage mid-session must NOT bounce straight back to
        // the Host the owner just left.
        .onChange(of: scenePhase) { previous, phase in
            guard phase == .active, previous == .background || previous == .inactive else { return }
            model.returnedToForeground()
        }
        // Hosts arrive (and re-sort) asynchronously over Bonjour, so keep focus on whichever row is
        // currently first until the owner moves it themselves - otherwise a late host that sorts ahead
        // leaves focus stranded on the wrong row (as it did on the second row before this).
        .onChange(of: model.hosts) { _, _ in pinInitialFocus() }
        // The Gallery row appears only after its probe answers (which lands after onAppear), so steer focus
        // onto it then, the same way a discovered host gets it.
        .onChange(of: model.galleryReachable) { _, _ in pinInitialFocus() }
        .onChange(of: focusedHost) { _, newValue in
            // Focus resting anywhere other than the expected initial row (the first host, or the Gallery row
            // when it is offered) is the owner navigating. Once that happens, stop steering.
            if newValue != expectedInitialFocus { ownerTookFocus = true }
        }
    }

    // Keep initial focus on the primary action while the screen is still settling, and only until the owner
    // has taken focus themselves (so a late-arriving host never yanks the cursor from under them). That
    // primary action is the first discovered host, or (when none is found yet) the OpenObject Gallery row
    // once its probe answers.
    private func pinInitialFocus() {
        guard !ownerTookFocus else { return }
        if let first = model.hosts.first {
            focusedHost = first.id
        } else if model.galleryReachable == true {
            focusedHost = Host.gallery.id
        }
    }

    // Where initial focus should rest: the first host, else the Gallery row when it is offered.
    private var expectedInitialFocus: String? {
        model.hosts.first?.id ?? (model.galleryReachable == true ? Host.gallery.id : nil)
    }

    @ViewBuilder private var discoveredHosts: some View {
        if model.hosts.isEmpty {
            emptyState
        } else {
            VStack(spacing: 24) {
                Text("Choose a Host")
                    .font(.headline).foregroundStyle(.secondary)
                VStack(spacing: 16) {
                    ForEach(model.hosts) { host in
                        Button { model.select(host) } label: {
                            HStack(spacing: 20) {
                                // Sized against the row's own label, not left at the default. An
                                // Image with no font takes the default body size, and tvOS spreads its
                                // type scale much wider than iOS does, so a body icon beside a .title2
                                // label reads far smaller here than the same pairing does on iPhone and
                                // iPad (where the picker runs a .body icon beside a .title3 label, a
                                // much closer pair). .title3 restores roughly the iOS proportion.
                                Image(systemName: "play.tv").font(.title3)
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

    // The empty state (§13): honest that no Host was found. When the public Gallery actually answers
    // (probe-gated), it offers the OpenObject Gallery so the screen is never a dead end. The Gallery row is
    // a focusable row styled like a discovered-Host row (photo.artframe instead of play.tv); its name says
    // what it is, so no instructional copy. Unreachable (or still probing) shows the reassurance copy.
    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 20) {
            if model.scanning {
                ProgressView().scaleEffect(1.6).tint(.white)
                Text("Looking for Hosts on your network…")
                    .font(.title3).foregroundStyle(.secondary)
            } else {
                Text("No Hosts found on your network.")
                    .font(.title3).foregroundStyle(.secondary)
                if model.galleryReachable == true {
                    VStack(spacing: 16) {
                        Button { model.connectToGallery() } label: {
                            HStack(spacing: 20) {
                                // photo.artframe reads smaller than play.tv at the same size (more built-in
                                // padding), so bump it to match the discovered-host rows. Carries the same
                                // .title3 as those rows, with .large keeping the relative compensation.
                                Image(systemName: "photo.artframe").font(.title3).imageScale(.large)
                                Text("OpenObject Gallery").font(.title2).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .focused($focusedHost, equals: Host.gallery.id)
                    }
                    .frame(width: 1500)
                } else {
                    Text("Your Apple TV is ready to connect. Once an OpenObject Host is running on your network, it will appear here automatically.")
                        .font(.callout).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 1100)
                }
            }
        }
        .frame(minHeight: 200)
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

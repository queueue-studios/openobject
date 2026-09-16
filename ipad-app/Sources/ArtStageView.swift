import SwiftUI
import UIKit
import DisplayCore
import DisplayUI

// The iPad art stage: the shared ArtStageCore (DisplayUI) rendering the rotation, plus the iOS-specific
// chrome hiding (status bar + home indicator) and the touch way back to the picker. The stage is
// zero-chrome by default; a tap reveals a "Hosts" control, and tapping THAT returns to the picker.
// The reveal is itself the speedbump: a stray tap on the art only shows the control (tap the art again to
// dismiss it) and never navigates, so leaving the piece takes a deliberate second tap on the control.
// ArtStageCore owns the crossfade, audio, idle/sleep marks, and screensaver defeat (shared with tvOS).
//
// The same tap-revealed overlay carries the local copy's one status line (HANDOFF §17), top-right: whether
// this device holds the rotation, so an owner knows it is ready before leaving the network. Nothing about it
// shows until the art is tapped, so the stage stays zero-chrome.
//
// While the iPad is playing its local copy, that status line is also the way in to the two offline rotation
// controls (§17, E26): it gains a chevron, and a tap drops a small panel beneath it with Order (Sequence /
// Shuffle) and Every (the duration). They exist only in that state; when the frame is live nothing new shows,
// which by itself says where settings normally live.
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool
    /// The local copy, or nil for a Host that is never held (the Demo Gallery).
    let localCopy: LocalCopy?
    /// The offline rotation controls' values and setters (E26).
    let offline: OfflineRotation
    let onExit: () -> Void

    @State private var showControls = false
    @State private var showRotation = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArtStageCore(player: player, host: host, pipeline: pipeline, muted: muted)
                .ignoresSafeArea()

            // Full-stage tap catcher (near-transparent fill, contentShape-reliable): a tap on the art
            // toggles the control, over stills and video alike. This reveal is the speedbump — a stray tap
            // only shows the control, it never leaves the art.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                }

            // The revealed controls: a deliberate tap on Hosts returns to the picker; the capsule opposite it is
            // the local copy's status. The root ignores the safe area so the art runs edge to edge, which also
            // strips it from this overlay, so the window's own top inset is padded back in: on an iPhone that is
            // the Dynamic Island band (the capsule had landed under it in the 2026-09-15 simulator pass), on an
            // iPad with the status bar hidden it is zero.
            if showControls {
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        onExit()
                    } label: {
                        Label("Hosts", systemImage: "chevron.backward")
                            .font(.headline)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    if let status = localCopyStatus {
                        VStack(alignment: .trailing, spacing: 8) {
                            if status.opensRotation {
                                // Offline: the capsule is a button and the panel hangs beneath it.
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) { showRotation.toggle() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Label(status.text, systemImage: status.icon)
                                        Image(systemName: showRotation ? "chevron.up" : "chevron.down")
                                            .font(.caption.weight(.semibold))
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(.ultraThinMaterial, in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(status.text). Rotation settings")
                                if showRotation { rotationPanel }
                            } else {
                                Label(status.text, systemImage: status.icon)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .accessibilityLabel(status.text)
                            }
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding()
                .padding(.top, windowTopInset)
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        // Hiding the overlay, or the frame coming back, closes the panel with it.
        .onChange(of: showControls) { _, shown in if !shown { showRotation = false } }
        .onChange(of: player.hostReachable) { _, reachable in if reachable { showRotation = false } }
    }

    // The two offline controls (E26), the control panel's own words. Order is a two-segment control, Every a
    // menu of presets whose label shows the current value (a non-preset value stays readable until one is
    // picked). Both apply at once; there is no Save, and no explanatory text.
    private var rotationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Order").font(.subheadline).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                Picker("Order", selection: Binding(
                    get: { offline.mode ?? .sequence },
                    set: { offline.setMode($0) }
                )) {
                    Text("Sequence").tag(RotationMode.sequence)
                    Text("Shuffle").tag(RotationMode.shuffle)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            HStack(spacing: 12) {
                Text("Every").font(.subheadline).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                Menu {
                    ForEach(Self.durationPresets, id: \.self) { ms in
                        Button {
                            offline.setDuration(ms)
                        } label: {
                            if ms == offline.durationMs {
                                Label(Self.durationLabel(ms), systemImage: "checkmark")
                            } else {
                                Text(Self.durationLabel(ms))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(Self.durationLabel(offline.durationMs ?? 8_000))
                        Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(.white)
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity)
    }

    /// The Every presets, in milliseconds: 15 s to 1 hour.
    static let durationPresets: [Int] = [15, 30, 60, 120, 300, 600, 1800, 3600].map { $0 * 1000 }

    /// A duration as the control panel would say it: "15 s", "1 min", "2 min 30 s", "1 hour".
    static func durationLabel(_ ms: Int) -> String {
        let s = max(1, ms / 1000)
        if s == 3600 { return "1 hour" }
        if s > 3600 { return s % 3600 == 0 ? "\(s / 3600) hours" : "\(s / 60) min" }
        if s < 60 { return "\(s) s" }
        return s % 60 == 0 ? "\(s / 60) min" : "\(s / 60) min \(s % 60) s"
    }

    // The key window's top safe-area inset (the sensor housing on an iPhone, which survives a hidden status
    // bar; zero on an iPad once the status bar is hidden). Read from the window because the root's
    // ignoresSafeArea leaves this view with none of its own.
    private var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    private struct CopyStatus {
        let icon: String
        let text: String
        /// True only for "Playing local copy": the state in which the capsule opens the rotation panel (E26).
        var opensRotation = false
    }

    // The four states of the one status line (§17), in priority order. "Playing local copy" wins whenever the
    // Host is not answering, since it also explains why edits made on the Host are not appearing. Nothing at
    // all for an empty rotation, or for a pass that is waiting to retry.
    private var localCopyStatus: CopyStatus? {
        guard let localCopy, localCopy.host?.id == host.id else { return nil }
        let s = localCopy.status
        if !player.hostReachable, s.hasCopy {
            return CopyStatus(icon: deviceIcon, text: "Playing local copy", opensRotation: true)
        }
        guard s.total > 0 else { return nil }
        if s.isSaving {
            return CopyStatus(icon: "arrow.down.circle", text: "Saving local copy · \(s.saved) of \(s.total)")
        }
        if s.isComplete {
            return CopyStatus(icon: "checkmark.circle", text: "Local copy ready")
        }
        if s.skippedForSpace > 0 {
            return CopyStatus(icon: "exclamationmark.circle", text: "\(s.saved) of \(s.total) fit on your \(deviceName)")
        }
        return nil
    }

    // Universal app: the device names itself from the idiom, as the picker's device-name line does.
    private var deviceName: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone"
    }

    private var deviceIcon: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }
}

/// The offline rotation controls' current values and setters (E26), passed in by the root so the stage stays a
/// plain view over the model.
struct OfflineRotation {
    let durationMs: Int?
    let mode: RotationMode?
    let setDuration: (Int) -> Void
    let setMode: (RotationMode) -> Void
}

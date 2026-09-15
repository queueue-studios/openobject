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
struct ArtStageView: View {
    let player: RotationPlayer
    let host: Host
    let pipeline: MediaPipeline
    let muted: Bool
    /// The local copy, or nil for a Host that is never held (the Demo Gallery).
    let localCopy: LocalCopy?
    let onExit: () -> Void

    @State private var showControls = false

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
                        Label(status.text, systemImage: status.icon)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(.ultraThinMaterial, in: Capsule())
                            .accessibilityLabel(status.text)
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
    }

    // The four states of the one status line (§17), in priority order. "Playing local copy" wins whenever the
    // Host is not answering, since it also explains why edits made on the Host are not appearing. Nothing at
    // all for an empty rotation, or for a pass that is waiting to retry.
    private var localCopyStatus: CopyStatus? {
        guard let localCopy, localCopy.host?.id == host.id else { return nil }
        let s = localCopy.status
        if !player.hostReachable, s.hasCopy {
            return CopyStatus(icon: deviceIcon, text: "Playing local copy")
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

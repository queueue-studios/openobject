import SwiftUI
import WebKit
import UIKit

// The Retro Arcade easter egg on iOS (HANDOFF §20): the SAME player/public/arcade.js the frame and the
// Mac display run, verbatim, in a web view over a bundled shell page (Resources/arcade.html). No port:
// the game is dependency-free canvas 2D that measures its own viewport, draws its square playfield to
// the shorter side with the starfield carrying any spare space, and re-flows live on resize, so every
// iPhone/iPad shape and rotation is its problem, already solved.
//
// Two ways in, one renderer:
//   • Watching a Host: the stage (ArtStageView) swaps the art for ArcadeStage while the Host's
//     `retroArcade` poll flag is up, so the Control Panel's hidden key sequence flips the frame, the
//     Mac, and this device together. Return to Art there ends it everywhere.
//   • Anywhere, offline included: a hidden touch code on the Host picker opens ArcadeScreen, this
//     hostless full-screen take. Its exit mirrors the stage exactly (tap reveals the Hosts capsule).
// Neither is ever persisted: the app always wakes to the picker or to art, never into the demo.

// MARK: - The web view

// The arcade's renderer: a locked-down WKWebView on the bundled shell, the ConnectedWebLayer treatment
// without the machinery the arcade does not need (no ready gate: the shell paints black instantly and the
// game is a local file; no session flags, no copy scheme, no fallback URL). The one failure it handles is
// the web content process dying, by reloading: the demo is stateless, so a reload IS recovery.
private struct ArcadeWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.navigationDelegate = context.coordinator
        // Black from the first frame (the stage is black; the default background would flash white).
        web.isOpaque = false
        web.backgroundColor = .black
        web.underPageBackgroundColor = .black
        web.scrollView.backgroundColor = .black
        // A display, not a browser: nothing scrolls, bounces, insets, previews or navigates.
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.allowsBackForwardNavigationGestures = false
        web.allowsLinkPreview = false
        web.isUserInteractionEnabled = false   // the demo takes no input; the hosting view owns the taps
        Self.load(web)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    private static func load(_ web: WKWebView) {
        guard let shell = Bundle.main.url(forResource: "arcade", withExtension: "html") else { return }
        web.loadFileURL(shell, allowingReadAccessTo: shell.deletingLastPathComponent())
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webViewWebContentProcessDidTerminate(_ web: WKWebView) {
            ArcadeWebView.load(web)
        }
    }
}

// MARK: - On the art stage

/// The arcade as the stage's content, shown by ArtStageView in place of ArtStageCore while the Host's
/// flag is up. Chrome (the tap-revealed Hosts capsule, status bar hiding) stays ArtStageView's, exactly
/// as it is over the art.
struct ArcadeStage: View {
    var body: some View {
        ArcadeWebView()
            .background(Color.black)
            .ignoresSafeArea()
    }
}

// MARK: - From the picker

/// The hostless full-screen arcade, the picker's hidden touch code's destination. Mirrors ArtStageView's
/// shell: zero chrome, a tap reveals the same Hosts capsule (the deliberate second tap back to the
/// picker), and the screen is kept awake the way the stage keeps it (ArtStageCore's idle-timer defeat,
/// which this view must carry itself since no stage is under it).
struct ArcadeScreen: View {
    let onExit: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var showControls = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArcadeStage()

            // Full-stage tap catcher, the stage's own speedbump: a stray tap only shows the control.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() }
                }

            if showControls {
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
                .foregroundStyle(.white)
                .padding()
                .padding(.top, windowTopInset)
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = (phase == .active)
        }
    }

    // The key window's top safe-area inset, as ArtStageView reads it (the sensor housing on an iPhone;
    // zero on an iPad with the status bar hidden).
    private var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }
}

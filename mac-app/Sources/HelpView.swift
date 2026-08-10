import SwiftUI

// A native Help window on the standard Help menu (E13).
//
// WHY NATIVE, NOT THE CONTROL PANEL'S HELP CARD. Auto Display shipped with a recorded requirement that
// the control panel's Help card explain it, and that requirement was missed. Reaching for it later
// looked obvious, but it puts a Mac-only feature's explanation on a different surface from the setting
// it explains, and Mac users look in the Help menu (Matt, 2026-08-10). So anything Mac-only is
// explained here, and the control panel keeps what belongs to it: Folder Collections, the viewer apps,
// Library / Rotation / Sleep. Nothing moved out of `player/`, so the frame is untouched.
//
// NOT AN APPLE HELP BOOK. A `.help` bundle would add HTML authored separately plus an `hiutil` index
// step to the build, and open in Help Viewer, which is a dated app next to the rest of this one. A
// SwiftUI window matches the app, has no build step, and is far easier to keep in step with the
// Setup Guide. The trade is losing Help-menu search, worth little across three topics.
//
// ONLY WHAT SURPRISES OR STRANDS SOMEONE GETS A TOPIC (Matt, 2026-08-10). Not "is it Mac-only?" —
// the Dock icon picker and Open / Stop / Return to Display are visible controls that do what their
// labels say, and documenting them would add words without adding understanding. This is the same
// call already recorded for the onboarding card, whose subtext was dropped as redundant (§20,
// 2026-07-02). Deliberately terse: `docs/MAC-DISPLAY-SETUP.md` is the long form and stays the place
// that teaches setup end to end. In-product help answers "what is happening right now".

let helpWindowID = "openobject-help"

struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // Replaces the default "OpenObject Help" item, which had nothing behind it: no
        // CFBundleHelpBookFolder / CFBundleHelpBookName is registered, and none is being added.
        CommandGroup(replacing: .help) {
            Button("OpenObject Help") { openWindow(id: helpWindowID) }
                .keyboardShortcut("?", modifiers: .command)
        }
    }
}

struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // "Works like a screen saver" LEADS, and is not merely denied. That simile is a decided
                // point (§20, 2026-08-06): it is the fastest mental model available, used while the
                // feature keeps its own name, and it already leads on the Settings caption, the Setup
                // Guide, and openobject.io. A first draft here opened with the Setup Guide's sentence
                // and cut the simile that follows it, leaving the screen saver idea to appear only as
                // a negation three bullets down. Do not reintroduce that ordering.
                topic(
                    "Auto Display",
                    "Auto Display works like a screen saver. With this feature, OpenObject can "
                    + "display your art full screen when your Mac has been inactive for a while. "
                    + "Set the wait time in Settings."
                ) {
                    // THE AUTO-LOCK DISCLOSURE, and it leads the bullets deliberately (Matt,
                    // 2026-08-10). A Mac with no screen saver still locks when its display turns off;
                    // Auto Display holds an idle-display-sleep assertion so that never happens, and
                    // our own guidance to set it SHORTER than the display-off timer is what
                    // guarantees the art wins the race. Net effect: auto-lock is suppressed for as
                    // long as art is up, which is indefinitely. There is no technical fix, since the
                    // assertion is what stops the screen blanking mid-piece; every full-screen media
                    // app makes the same trade. Disclosure is the answer.
                    point(
                        "IMPORTANT: While Auto Display is showing art, your Mac stays awake and will "
                        + "not lock on its own. If you want your Mac locked while you are away, press "
                        + "Control-Command-Q before you go, or leave Auto Display set to Never."
                    )
                    point(
                        "Auto Display is not an official macOS screen saver and does not appear in "
                        + "the screen saver list. You do not need to change your screen saver settings."
                    )
                    point(
                        "Your Mac may be set to turn off its display after a period of inactivity "
                        + "(System Settings > Lock Screen). If so, it should be set to a timeframe "
                        + "longer than the OpenObject Auto Display setting, else your screen goes "
                        + "dark first."
                    )
                    point(
                        "Don’t worry, OpenObject warns you if you choose an Auto Display setting "
                        + "that is in conflict with your Lock Screen setting."
                    )
                }

                topic(
                    "Chrome",
                    "OpenObject uses Google Chrome to show your art full screen, with nothing else "
                    + "on screen. It helps your art display consistently across your screens."
                ) {
                    // Scoped to the whole product, not to one feature: Chrome is required for every
                    // display however it starts, and an earlier draft read closely enough to the Auto
                    // Display topic to be taken as that feature's requirement (Matt, 2026-08-10).
                    point(
                        "Chrome must be installed. Without it, the display cannot open and "
                        + "OpenObject will not work as expected."
                    )
                    point(
                        "OpenObject uses its own separate Chrome profile, so your bookmarks, tabs, "
                        + "history, and other Chrome data are not touched."
                    )
                }

                // "Either", never "either or both": AppMode is .host OR .viewer, one persisted choice.
                topic(
                    "Hosting and Viewing",
                    "A Host holds your art and serves it to your screens. A Viewer simply shows art "
                    + "from a Host elsewhere on your network. This Mac can be either."
                ) {
                    point(
                        "Host OpenObject on this Mac and your art lives here, managed through the "
                        + "control panel from any browser on your network."
                    )
                    point(
                        "Access another Host instead, such as another Mac or an Infinite Objects "
                        + "XXL frame, and this Mac becomes another screen for the art already "
                        + "hosted there."
                    )
                    point(
                        "Apple TV and iPad are always Viewers. They need a Host running on the "
                        + "same network."
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 440, idealWidth: 460, minHeight: 420, idealHeight: 620)
    }

    @ViewBuilder
    private func topic(
        _ title: String, _ lede: String, @ViewBuilder points: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(lede).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) { points() }
        }
    }

    // A hanging bullet: the dot stays in its own column so wrapped lines line up under the text.
    @ViewBuilder
    private func point(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("•").foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

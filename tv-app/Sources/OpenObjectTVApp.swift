import SwiftUI

// OpenObject Apple TV app — entry point (TVOS-APP-PLAN §14 Phase C).
//
// A thin tvOS shell over the shared DisplayCore engine (../display-core). It takes exactly one role,
// Display (§3): it finds a Host on the LAN, the owner picks one, and it renders that Host's rotation
// full screen with zero chrome. It runs no server and owns no art. This is the C1 skeleton; the Host
// picker, the art stage, and the poll/advance driver arrive in later Phase C checkpoints.

@main
struct OpenObjectTVApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

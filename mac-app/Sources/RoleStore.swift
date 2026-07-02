import Foundation

// The app's chosen role, persisted across launches (MAC-APP-PLAN §B3 / §8). A Mac can either run
// its own Host, or act as a Display/Control viewer of another Host it found on the network (e.g. an
// XXL frame). This is the "run my own vs. use an existing one" choice; it is remembered so the app
// resumes in the same role next launch.
enum AppMode: Equatable {
    case host                                   // run our own bundled engine; this Mac is a Host
    case viewer(hostId: String, name: String)   // view/control a chosen remote Host; no local server
}

@MainActor
final class RoleStore: ObservableObject {
    @Published private(set) var mode: AppMode
    // Whether the owner has made an explicit Host-vs-Viewer choice. Until they have, the first-run
    // prompt is offered whenever another Host is found on the network (§B3 onboarding). A fresh Mac
    // with no other Host around never sees it (zero friction) and just runs as a Host.
    @Published private(set) var hasChosen: Bool

    private let defaults = UserDefaults.standard
    private let modeKey = "appMode"
    private let idKey = "viewerHostId"
    private let nameKey = "viewerHostName"
    private let chosenKey = "hasChosenRole"

    init() {
        hasChosen = defaults.bool(forKey: chosenKey)
        if defaults.string(forKey: modeKey) == "viewer", let id = defaults.string(forKey: idKey) {
            mode = .viewer(hostId: id, name: defaults.string(forKey: nameKey) ?? "OpenObject")
        } else {
            mode = .host // zero-friction default: a fresh Mac just runs its own Host
        }
    }

    func runAsHost() {
        mode = .host
        defaults.set("host", forKey: modeKey)
        defaults.removeObject(forKey: idKey)
        defaults.removeObject(forKey: nameKey)
        markChosen()
    }

    func view(hostId: String, name: String) {
        mode = .viewer(hostId: hostId, name: name)
        defaults.set("viewer", forKey: modeKey)
        defaults.set(hostId, forKey: idKey)
        defaults.set(name, forKey: nameKey)
        markChosen()
    }

    private func markChosen() {
        hasChosen = true
        defaults.set(true, forKey: chosenKey)
    }
}

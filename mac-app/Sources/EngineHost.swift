import Foundation
import AppKit

// Runs the bundled OpenObject engine as a child process — the Mac app's HOST role
// (MAC-APP-PLAN §B2). It locates the bundled Node runtime and player/ snapshot (staged into
// Resources by bundle-engine.sh, §B1b), points the engine's library DB + uploads at a writable
// Application Support folder (§B6 — the app bundle itself is read-only and ships no data/), spawns
// `node server.js`, and waits for /healthz to confirm it is serving. It owns the process lifecycle:
// started on launch, stopped cleanly on quit.
@MainActor
final class EngineHost: ObservableObject {
    enum Status: Equatable {
        case idle
        case starting
        case running(name: String)
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    // This Host's stable id (from /healthz), so the UI can mark the local Host as "This Mac" in the
    // discovered-Hosts list. Nil until the Host answers.
    @Published private(set) var hostId: String?

    // Fixed for now; the app owns the port and hands it to the Display (Chrome) in B4.
    let port = 3000
    var baseURL: URL { URL(string: "http://localhost:\(port)")! }
    var controlURL: URL { baseURL }
    var displayURL: URL { baseURL.appendingPathComponent("display") }

    private var process: Process?
    private var tearingDown = false

    // The engine's writable home: ~/Library/Application Support/OpenObject/ (§B6). db.js honors
    // OO_DATA_DIR / OO_UPLOADS_DIR, so the read-only bundled player/ writes here instead.
    private var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenObject", isDirectory: true)
    }

    // MARK: - Lifecycle

    func start() {
        guard process == nil else { return }
        status = .starting
        Task { await startAfterPreflight() }
    }

    // Don't stack a second server on top of one already running on this Mac (a stray dev/preview
    // server, or a leftover from a previous run). Two OpenObject servers on one machine contend on
    // mDNS and can break openobject.local resolution (the 2026-07-12 outage). Surface it plainly
    // instead of spawning a duplicate that just fails to bind the port and reports a vaguer error.
    private func startAfterPreflight() async {
        let serving = await portAlreadyServing()
        guard case .starting = status, process == nil else { return } // stop()/a role switch intervened
        if serving {
            status = .failed("Another OpenObject server is already running on this Mac (port \(port)). Quit it, then reopen OpenObject.")
            return
        }
        launchEngine()
    }

    // True if something already answers /healthz on our port, i.e. an OpenObject engine is already up
    // on this Mac. A refused connection (nothing there) returns false fast.
    private func portAlreadyServing() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("healthz"))
        req.timeoutInterval = 1.0
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
        return true
    }

    private func launchEngine() {
        guard let nodeURL = Bundle.main.url(forResource: "node", withExtension: nil) else {
            status = .failed("Bundled Node runtime is missing from the app.")
            return
        }
        let serverJS = Bundle.main.resourceURL!
            .appendingPathComponent("player", isDirectory: true)
            .appendingPathComponent("server.js")
        guard FileManager.default.fileExists(atPath: serverJS.path) else {
            status = .failed("Bundled player is missing from the app.")
            return
        }

        let dataDir = supportDir.appendingPathComponent("data", isDirectory: true)
        let uploadsDir = supportDir.appendingPathComponent("uploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: uploadsDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = nodeURL
        proc.arguments = [serverJS.path]
        var env = ProcessInfo.processInfo.environment
        env["OO_DATA_DIR"] = dataDir.path
        env["OO_UPLOADS_DIR"] = uploadsDir.path
        env["PORT"] = String(port)
        proc.environment = env
        // Surface engine logs in the app's stdout/stderr (visible in Console / Xcode) for debugging.
        proc.standardOutput = FileHandle.standardOutput
        proc.standardError = FileHandle.standardError

        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                // A termination we did NOT initiate (a crash) surfaces as an error; an intentional
                // stop() has already set tearingDown and moved status to idle.
                if !self.tearingDown, case .running = self.status {
                    self.status = .failed("The OpenObject engine stopped unexpectedly (code \(code)).")
                }
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            status = .failed("Could not launch the engine: \(error.localizedDescription)")
            return
        }

        Task { await waitForHealthy() }
    }

    func stop() {
        guard let proc = process else { return }
        tearingDown = true
        process = nil
        status = .idle
        hostId = nil
        proc.terminationHandler = nil
        proc.terminate() // SIGTERM — the server withdraws its Bonjour record and exits (A2/A3)

        // Give it a moment to exit cleanly; hard-kill as a last resort so quit never hangs or
        // orphans the node child.
        let deadline = Date().addingTimeInterval(3)
        while proc.isRunning && Date() < deadline { usleep(50_000) }
        if proc.isRunning { kill(proc.processIdentifier, SIGKILL) }
        tearingDown = false
    }

    // MARK: - Health

    private func waitForHealthy() async {
        let health = baseURL.appendingPathComponent("healthz")
        for _ in 0..<80 { // ~20s at 250ms
            if process == nil { return } // stopped while we were waiting
            if let identity = await fetchIdentity(health) {
                if process != nil {
                    hostId = identity.id
                    status = .running(name: identity.name)
                }
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if case .starting = status {
            status = .failed("The engine did not start responding on port \(port).")
        }
    }

    private func fetchIdentity(_ url: URL) async -> (id: String, name: String)? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 1.5
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return (id: (obj["id"] as? String) ?? "", name: (obj["name"] as? String) ?? "OpenObject")
    }
}

import SwiftUI
import AppKit

// The main window. It is role-aware (MAC-APP-PLAN §B3): the top reflects whether this Mac is running
// its own Host or viewing a chosen remote Host, and the discovered-Hosts list below is selectable to
// switch between them. First-run onboarding presentation + list-growth polish come in B3b-2.
struct ContentView: View {
    @EnvironmentObject private var engine: EngineHost
    @EnvironmentObject private var discovery: HostDiscovery
    @EnvironmentObject private var roleStore: RoleStore

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("OpenObject")
                .font(.title.weight(.semibold))

            if showOnboarding {
                // A focused first-run choice: just the card (the found Hosts are its buttons, so the
                // usual list below would be redundant, and it also freed the card from being squeezed).
                onboardingCard
            } else {
                roleSection
                Divider()
                hostsView
            }
        }
        .padding(40)
        // Fixed default width (420), growable to read a long host name; height follows the content so
        // the window grows to fit a few Hosts and the list scrolls only when there are many (see
        // hostsView). Resizes aren't persisted — see WindowConfigurator.
        .frame(minWidth: 420, maxWidth: .infinity)
        .background(WindowConfigurator())
    }

    // MARK: - Top: the current role

    @ViewBuilder private var roleSection: some View {
        switch roleStore.mode {
        case .host:
            hostStatusView
        case .viewer(_, let name):
            viewerStatusView(name: name)
        }
    }

    @ViewBuilder private var hostStatusView: some View {
        switch engine.status {
        case .idle, .starting:
            Label("Starting the host…", systemImage: "hourglass")
                .foregroundStyle(.secondary)
        case .running(let name):
            VStack(spacing: 4) {
                Label("Host running", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(name).font(.callout)
                Text(engine.baseURL.absoluteString)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Open Control Panel") { openControlPanel() }
                .buttonStyle(.borderedProminent)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private func viewerStatusView(name: String) -> some View {
        VStack(spacing: 4) {
            Label("Viewing", systemImage: "display")
                .foregroundStyle(.secondary)
            Text(name).font(.callout)
        }
        Button("Open Control Panel") { openControlPanel() }
            .buttonStyle(.borderedProminent)
        Button("Run OpenObject on this Mac") { roleStore.runAsHost() }
    }

    // MARK: - First-run onboarding (only when another Host is found)

    // Hosts that aren't this Mac's own running Host.
    private var otherHosts: [HostDiscovery.Host] {
        discovery.hosts.filter { $0.id != engine.hostId }
    }

    // Offer the choice only when there's a real one to make: the owner hasn't chosen yet, our own
    // Host is up (so `otherHosts` correctly excludes it), and at least one other Host is present. A
    // fresh Mac with no other Host around never sees this and just runs as a Host (zero friction).
    private var showOnboarding: Bool {
        !roleStore.hasChosen && engine.hostId != nil && !otherHosts.isEmpty
    }

    @ViewBuilder private var onboardingCard: some View {
        VStack(spacing: 12) {
            Text("OpenObject is already on your network")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Use this Mac to view and control it, or run a separate OpenObject here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(otherHosts) { host in
                    Button {
                        roleStore.view(hostId: host.id, name: host.name)
                    } label: {
                        Text("View \(host.name)").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button {
                    roleStore.runAsHost()
                } label: {
                    Text("Run OpenObject on this Mac").frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.25)))
    }

    // MARK: - Bottom: discovered Hosts (selectable to switch roles)

    @ViewBuilder private var hostsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OpenObject hosts on your network")
                .font(.subheadline.weight(.semibold))
            if discovery.hosts.isEmpty {
                Text("Searching…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if orderedHosts.count <= maxRowsBeforeScroll {
                // A few Hosts: show them all; the window grows to fit (Matt's Q2, 2026-07-02).
                ForEach(orderedHosts) { host in
                    hostRow(host)
                }
            } else {
                // Many Hosts (rare): cap the height and scroll, so the window doesn't run off-screen.
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(orderedHosts) { host in
                            hostRow(host)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: rowHeight * Double(maxRowsBeforeScroll))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private let maxRowsBeforeScroll = 5
    private let rowHeight: Double = 26

    @ViewBuilder private func hostRow(_ host: HostDiscovery.Host) -> some View {
        let active = isActive(host)
        let local = (host.id == engine.hostId)
        if active {
            // The Host currently wired up: a prominent, checkmarked label — NOT a disabled button
            // (a disabled control renders grayed, which wrongly dimmed the active row).
            rowLabel(host, active: true, local: local)
        } else {
            // Another Host: a clickable button that switches to it.
            Button {
                if local { roleStore.runAsHost() } else { roleStore.view(hostId: host.id, name: host.name) }
            } label: {
                rowLabel(host, active: false, local: local)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private func rowLabel(_ host: HostDiscovery.Host, active: Bool, local: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: active ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                .foregroundStyle(active ? Color.green : Color.secondary)
            Text(host.name)
                .fontWeight(active ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
            if let version = host.version {
                Text("v\(version)").font(.footnote).foregroundStyle(.secondary)
            }
            if local {
                Text("· This Mac").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    // The connected/wired Host first, then the rest in discovery's alphabetical order (Matt,
    // 2026-07-02). discovery.hosts is already sorted by name.
    private var orderedHosts: [HostDiscovery.Host] {
        let hosts = discovery.hosts
        return hosts.filter { isActive($0) } + hosts.filter { !isActive($0) }
    }

    private func isActive(_ host: HostDiscovery.Host) -> Bool {
        switch roleStore.mode {
        case .host: return host.id == engine.hostId
        case .viewer(let id, _): return host.id == id
        }
    }

    private func openControlPanel() {
        switch roleStore.mode {
        case .host:
            NSWorkspace.shared.open(engine.controlURL)
        case .viewer(let id, _):
            guard let host = discovery.hosts.first(where: { $0.id == id }) else { return }
            Task {
                if let url = await discovery.resolveURL(for: host) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }
}

// Applies one-time NSWindow tweaks SwiftUI doesn't expose declaratively. Here it turns OFF frame
// restoration so the window always opens at its default size — the user may resize it (e.g. to reveal
// a long host name) but the resize is not remembered across launches.
private struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            // Don't remember the frame across launches: SwiftUI autosaves the window frame (and macOS
            // restores it) independently, so a prior session's resize would otherwise carry over. With
            // autosave off + not restorable, the window reopens at its content-driven size each launch.
            window.isRestorable = false
            window.setFrameAutosaveName("")
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

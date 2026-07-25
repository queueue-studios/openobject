// The rotation engine: the native port of player/public/display.js's core (§8), the heart of the
// Display role. Given each /api/display poll it decides WHICH renderable piece is on screen and, via
// its timing signals, WHEN to advance — folding library and settings changes into a running rotation
// without restarting the loop.
//
// It is deliberately pure and synchronous: no timers, no networking, no UI. A driver (Phase C) polls
// the DisplayClient every ~5s and calls `apply()`, renders `screen`, and — once the current piece is
// actually on screen — waits `durationMs` before calling `advance()`. Keeping time EXTERNAL is what
// makes the whole engine deterministically testable (drive `advance()` by hand); the Shuffle RNG is
// injectable for the same reason.
//
// Two things differ from display.js, both because tvOS is native (§2, §6):
//   • It rotates ONLY through items this Display can render (CapabilityFilter): connected / SVG / WebM
//     are skipped. A rotation of nothing renderable — e.g. a pinned Connected piece (§8) — is empty
//     here and shows the splash, never a substitute.
//   • It renders no art itself; it emits `screen` (idle / sleeping / playing) for the UI and media
//     pipeline to realize.
//
// Concurrency: a plain (non-Sendable) reference type. Phase C creates and drives it on the main actor;
// it is never shared across concurrency domains.

public final class RotationEngine {
    /// What the UI should present right now.
    public enum Screen: Equatable, Sendable {
        case idle                     // the branded splash: empty rotation or nothing renderable (§4)
        case sleeping                 // the dimmed sleep screen (§13)
        case playing(DisplayItem)     // render this piece
    }

    /// The current screen. A driver observes this and renders it.
    public private(set) var screen: Screen = .idle
    /// The global equal-time duration for every piece (from the Host). The driver waits this long, from
    /// when the current piece is on screen, before calling `advance()`.
    public private(set) var durationMs: Int = 8000
    /// Whether the driver should run the advance timer. A lone or pinned piece holds forever (false),
    /// and nothing advances while asleep.
    public var autoAdvances: Bool { renderable.count > 1 && !isSleeping }

    // Internal rotation state (mirrors display.js).
    private var renderable: [DisplayItem] = []   // the filtered, renderable rotation
    private var mode: RotationMode = .sequence
    private var pos = -1                          // index in `renderable` of the current piece
    private var currentID: String?               // its id — survives reordering across polls
    private var currentSig: String?              // fit+source signature — detects a live restyle
    private var started = false
    private var isSleeping = false
    private var shuffleBag: [Int] = []           // remaining indices in this Shuffle pass
    private var itemsListSig = ""                // renderable ids; the bag resets only when this changes

    private let filter = CapabilityFilter()
    private var rng: any RandomNumberGenerator

    /// - Parameter rng: randomness for Shuffle order. Inject a seeded generator in tests for
    ///   deterministic passes; defaults to the system generator.
    public init(rng: any RandomNumberGenerator = SystemRandomNumberGenerator()) {
        self.rng = rng
    }

    /// Fold a fresh /api/display poll into the running rotation (§8). Safe to call on every poll.
    public func apply(_ response: DisplayResponse) {
        durationMs = response.durationMs
        mode = response.mode

        // Sleep (§13) replaces playback with the dimmed screen; waking resumes below.
        if response.asleep {
            if !isSleeping { isSleeping = true; resetPlayback(); screen = .sleeping }
            return
        }
        isSleeping = false

        // Pin (§7): a pinned piece is the whole rotation. Mirror display.js's client-side collapse (the
        // Host also collapses `items`, so this is usually a no-op).
        let pinned = response.pinnedId.flatMap { id in response.items.first { $0.id == id } }
        let rawItems = pinned.map { [$0] } ?? response.items

        // Rotate only through renderable pieces; connected / SVG / WebM are skipped (§2, §6). A pinned
        // Connected piece collapses to empty here -> splash, never a substitute (§8).
        let next = rawItems.filter { $0.isRenderable(using: filter) }

        // Reset the Shuffle bag ONLY when the renderable set/order actually changes, so an unchanged
        // poll never restarts the pass (§8).
        let nextSig = next.map(\.id).joined(separator: "|")
        if nextSig != itemsListSig {
            shuffleBag = []
            itemsListSig = nextSig
        }
        renderable = next

        if renderable.isEmpty { showIdle(); return }

        // Track the current piece across reorders; -1 if it was deleted.
        if let currentID {
            pos = renderable.firstIndex { $0.id == currentID } ?? -1
        }
        if !started || pos < 0 {
            advance()                                     // (re)start, or skip a deleted current
        } else if sig(renderable[pos]) != currentSig {
            show(renderable[pos])                          // current piece restyled (e.g. Fit) -> re-render
        }
    }

    /// Advance to the next piece. A driver calls this `durationMs` after the current piece appeared; a
    /// lone piece is a no-op (the next pick is the same piece).
    public func advance() {
        guard !renderable.isEmpty else { showIdle(); return }
        pos = pickNext()
        let item = renderable[pos]
        if item.id != currentID { show(item) }
    }

    // MARK: - Internals

    private func pickNext() -> Int {
        let n = renderable.count
        guard n > 1 else { return 0 }
        if mode == .shuffle {
            if shuffleBag.isEmpty {
                shuffleBag = shuffledIndices(n)
                // Avoid an immediate repeat across the pass boundary (mirrors display.js).
                if shuffleBag.first == pos && shuffleBag.count > 1 {
                    shuffleBag.append(shuffleBag.removeFirst())
                }
            }
            return shuffleBag.removeFirst()
        }
        return (pos + 1) % n                               // sequence
    }

    private func show(_ item: DisplayItem) {
        pos = renderable.firstIndex { $0.id == item.id } ?? pos
        currentID = item.id
        currentSig = sig(item)
        started = true
        screen = .playing(item)
    }

    private func showIdle() {
        resetPlayback()
        screen = .idle
    }

    private func resetPlayback() {
        started = false
        pos = -1
        currentID = nil
        currentSig = nil
        shuffleBag = []
    }

    // What determines how a renderable piece looks: a change here (e.g. a live Fit flip) re-renders it
    // in place, matching display.js's `sig`. For a native item that is fit + the media source.
    private func sig(_ item: DisplayItem) -> String {
        "\(item.fit.rawValue)|\(item.src ?? item.filename ?? item.id)"
    }

    // Fisher-Yates over 0..<n using the injected RNG (mirrors display.js's shuffle exactly, so a seeded
    // generator yields deterministic passes in tests).
    private func shuffledIndices(_ n: Int) -> [Int] {
        var a = Array(0..<n)
        var i = n - 1
        while i > 0 {
            let j = Int(rng.next() % UInt64(i + 1))
            a.swapAt(i, j)
            i -= 1
        }
        return a
    }
}

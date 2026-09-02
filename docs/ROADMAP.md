# OpenObject roadmap: the one list of open work

**Organized by state, not by area**, because the everyday question is "what is committed
and available to start next?" and the old area grouping buried the answer among things
that were blocked, parked, or never intended. Area is a column now, so that view survives.

**The states, in the order they matter:**

| State | Means |
|-------|-------|
| **Committed** | Decided, no blockers. This is the queue. Start here. |
| **Blocked** | Intended, but something outside our control prevents starting. Every row says what. |
| **Deferred** | Worth doing, deliberately not now. Every row says what would resume it. |
| **Candidate** | A valid idea we have not decided to do. |
| **Checks** | Verify or observe, not build. |
| **Closed** | Considered and decided against, or dropped. Not a to-do. |

**Candidate vs Deferred** is the pair that blurs, so: Candidate means *we have not decided
whether to do it*; Deferred means *we decided it is worth doing, just not yet*.

**There is no Done section.** When a row ships, delete it and move the design record into
`HANDOFF.md` §20; the ID retires with it. §20 is the record of what is done, and a second
copy here would drift, which is the exact failure this file was created to fix.

**This file holds no reasoning.** Every row points at the design record that does. That
split is deliberate: duplicated reasoning is what let four separate lists drift apart
(§17, the HANDOFF status line, `TVOS-APP-PLAN.md` phases, and scattered notes), so a row
here is one line plus a pointer, and it is cheap to keep honest.

**IDs are stable and never reused.** Talk about work by its ID. A row that changes state
keeps its ID, unless it moves into Closed, where it is renumbered `D…` and its old ID
retires (as `W5` did on becoming `E19`).

Size is a rough sense of the job, not a promise.

Last swept: 2026-09-01.

---

## Committed

Decided, unblocked, ready to start.

| ID | Area | Item | Design record | Notes |
|----|------|------|---------------|-------|
| E3 | Apps (iPad) | Offline / portable playback: the **iPad** holds its own art and keeps playing with no network. **Committed 2026-08-10** (Matt). iPad only, permanently: the Apple TV variant is closed by tvOS storage limits (D14) | HANDOFF §17 "Offline / portable playback"; `TVOS-APP-PLAN.md` §9 | Medium. Needs a persistent store, a "Download for offline" choice, the manifest persisted, and an offline launch path |
| E23 | Apps (tvOS, iPad) | Host picker empty state: restore the "waiting, not failed" copy and stop suppressing it when the Gallery row shows, rename toward **OpenObject Demo Gallery**, and disable Connect on an empty address field. **Unblocked 2026-09-01**: both apps are live at 1.6.2, so the fixes ship in the next app build | HANDOFF §17 "Host picker empty state" | Small. Both apps: tvOS has the same defects and drew a luckier reviewer |
| E1 | Apps (iPad) | Connected Collections on the iPad/iPhone app via `WKWebView`, plus the skip mechanism and the "Chrome Only" pill. **Unblocked 2026-09-01**: the iOS build is approved and live, so the external wall is gone | HANDOFF §17 "Connected Collections on the viewer apps" | **Large**, and deliberately not queued ahead of the 1.9.0 release. **One check** now opens it: Connected art on a real **iPhone** (inkField cleared 2026-09-01). Running the shipped app on an iPhone does not count, since it renders no Connected art |

## Blocked

Intended work that cannot start yet. The blocker is external; when it clears, the row moves
to Committed.

**Nothing is blocked right now** (2026-09-01). The last two external blockers, E16 and E1, both
cleared when Apple approved the iOS build. Keep the section: it is where a row goes when something
outside our control stops it, and it should stay visibly empty rather than be deleted.

## Deferred

Worth doing, deliberately not now.

| ID | Area | Item | Resumes when | Design record |
|----|------|------|--------------|---------------|
| E14 | Mac app | Move the Settings window to tabs | Settings reaches **five or six rows**. It has two (Dock icon, Auto Display), and tabs would cost a click and look emptier than the single pane (Matt, 2026-08-02) | HANDOFF §20 2026-08-06 Auto Display record. Small |
| E6 | Apps (tvOS, iPad) | Retro Arcade easter egg on tvOS / iPad. `arcade.js` is dependency-free canvas 2D and maps onto SpriteKit or SwiftUI Canvas; a Siri Remote D-pad is a better trigger than a keyboard | Whenever wanted. Post-v1 by choice, no external condition | `TVOS-APP-PLAN.md` §5. Medium |
| E2 | Apps (iPad) | Golden Lining as a pre-rendered looping video, a per-piece WebKit fallback | Nothing: this one **closes** rather than resumes, and is now one check away, the iPhone. Provisionally retired already, since the piece rendered correctly on a real iPad | HANDOFF §17 "Golden Lining as a pre-rendered video" |

## Candidate

Valid ideas, not decided.

| ID | Area | Item | Design record |
|----|------|------|---------------|
| E22 | Display | Ambient letterbox background: an optional setting that fills a Fit piece's black bars with gradients drawn from the piece's own colours, instead of black. **Parked, not committed** (Matt, 2026-08-09) | HANDOFF §17 "Ambient letterbox background". Medium. Opt-in, default black, since the bare black stage is a stated product rule. Most visible on the square frame, where nearly everything letterboxes |

## Checks

Verify or observe, not build. No action unless a check comes back wrong or a symptom recurs.

| ID | Area | Item | Notes |
|----|------|------|-------|
| W3 | Frame | Switching Display Source from a folder back to the Library once made the frame's `display.js` go fully black. Never reproduced, and the native Apple TV handled the same switch fine | Repro path: Mac Chrome at `http://openobject.local/display` with DevTools open during the switch. memory: tvos-app-plan-execution (2026-07-30) |

### Pending device verification

Built and verified as far as it can be here, but not seen on the real hardware it affects.
**A row is added in the same commit as the change**, so it cannot be forgotten, and cleared
when the check is done or when the build carrying it ships.

| Device | What to check | Landed |
|--------|---------------|--------|
| Frame (fresh install) | The `install.sh` Wi-Fi handoff now delegates to `nm-handoff.sh` with the guard off. The retrofit path is device-proven, but the fresh-install path cannot be exercised without installing a new frame, which nobody can currently do | `36b6ffa`, 2026-08-08 |
| Apple TV | The per-Host row icon in the picker now matches its label size. Confirm on the real Apple TV, since that is where the undersized icon was noticed; the simulator before/after only proves the change took effect | `8adbbbe`, 2026-08-08 |
| Apple TV | E23's picker empty state: the headline reads as waiting, the Gallery row says **Demo**, and Connect is greyed until an address is typed. Simulator-verified; the real remote's focus behaviour around a disabled Connect is what the device pass is for | this change |
| iPad + iPhone | The same three E23 fixes. Verified on both idioms in the simulator with the frame powered down. **Not seen rendered: the device-name line** (`Your iPad` / `Your iPhone`), which only draws when the Gallery is unreachable too, so forcing it needs a moment with no Host *and* no internet | this change |

## Closed: decided against, or not worth tracking

Settled. Do not re-pitch without new information; if the answer changes, say what changed.
Rows that were dropped rather than rejected are here for the same reason: so a later sweep
of §20 and the memory files cannot quietly resurrect them as new items.

| ID | Item | When |
|----|------|------|
| D1 | Library pagination. Keep one growing list; the Show All / In-rotation filter solved the clutter | 2026-06-25 |
| D2 | A sort control on the Settings Connected Collections list. It is a fixed curated shelf, not a growing set | 2026-06-25 |
| D3 | "Paste any URL" / a general live on-chain resolver | HANDOFF §17/§20 |
| D4 | A real macOS `.saver` screen saver. It cannot host Chrome, and a `WKWebView` inside it is broken and would be a second, worse renderer | 2026-08-02 |
| D5 | Opening the display at login. Easy to build; Matt does not want it | 2026-08-02 |
| D6 | The Host pre-renders every Connected piece for the viewer apps | `TVOS-APP-PLAN.md` §2 |
| D7 | Retro Arcade: the alternate marquee PNG (IP-risky) and the capture / dual-fighter mechanic (conflicts with never-die). Both built, both abandoned | memory: retro-arcade-attract-easter-egg |
| D8 | `willReadFrequently` as the Golden Lining WebKit fix. Tried, did not work | memory: golden-lining-webkit-safari-broken |
| D9 | Privacy policy wording for the Gallery being an internet Host rather than a LAN Host. Substantively still true (nothing collected); dropped until someone raises it | 2026-08-08 |
| D10 | A power assertion holding the Mac awake while it serves a folder. The Setup Guide already tells owners to turn on "Prevent automatic sleeping when the display is off", which covers the case, so the code would only have deleted a line of documentation. The one gap it would have closed, a laptop serving on battery, is not a case Matt wants to support: holding a long-running connection awake to drain a battery is the wrong behavior to build. Design record stays at HANDOFF §17 | 2026-08-08 |
| D11 | Watching for a recurrence of the frame's Bonjour / Wi-Fi drops. The `iwlwifi` power-save fix shipped and is reboot-confirmed (§20 2026-07-28); passive watching adds nothing, and a recurrence would simply be a new bug | 2026-08-08 |
| D12 | Eyeballing inkField on the real frame at `framePixelDensity` 1. Accepted as shipped on the harness verification (§20 2026-07-29) | 2026-08-08 |
| D13 | Capturing the Gatekeeper "downloaded from the Internet" prompt from a real download. The Setup Guide's wording stands unverified; worst case an owner meets one unexplained warning once | 2026-08-08 |
| D14 | Offline / portable playback on **Apple TV**. tvOS guarantees an app 500 KB of persistent storage and may delete cached media exactly when the device is unplugged and the app is not running, so "load at home, carry it, plug in with no network" cannot be made durable there. Closed by the platform, not by preference; the iPad version stays alive as E3. Do not re-open on parity grounds | 2026-08-08 |
| D15 | Real restart / shutdown, i.e. making the panel go genuinely dark instead of showing its own no-signal test pattern. Both routes need hardware Matt does not want: a smart plug, or HDMI-CEC, which PC HDMI outputs (Intel integrated graphics included) generally do not wire up, so it would mean a USB CEC dongle. Unplugging is an acceptable power-off for a wall-mounted frame, and Matt is happy with how Shut down behaves. Sleep already covers the everyday "screen dark, art stopped" case with no test pattern | 2026-08-08 |
| D16 | Single-file / prebuilt release image (the USB installer as a Release asset). Closed off the roadmap 2026-08-08: validating it needs a second XXL to wipe, Matt considers his frame done and untouchable, and he does not expect ever to have another, so the row could never become actionable. Shipping it unvalidated is worse than not shipping it, since the automated part is the destructive part and the manual path is proven on real hardware. **The doable parts were split out first and live on as E20.** The full design record stays at HANDOFF §17 "Prebuilt release image", intact for a stranded owner who ever wants to pick it up | 2026-08-08 |
| D17 | Syncing multiple screens so they show the **same** piece at the same moment, as part of E12. Decided against 2026-08-10 (Matt): each screen runs its own rotation. The price is the reason. The rotation is entirely client-side (`setTimeout(advance, durationMs)`, a local `pos`, a client-side shuffle bag; `/api/display` returns a list with no cursor), so syncing means making the server authoritative about what is showing now. That collides head-on with a deliberate design point: the next advance is armed from the piece's **reveal**, not from `advance()`, because a Connected piece can take seconds to paint and timing from `advance()` would rob it of visible duration. A server clock reintroduces exactly that bug. Worst of all it is a change to `player/`, shared with the frame, so a Mac-only feature would be rewriting the frame's proven playback loop. **If it is ever re-pitched**, the one fact that could reopen it is Apple mirroring identical screen-saver content across displays rather than running each screen independently, which is unverified | 2026-08-10 |
| D18 | SMB pull as a source. **Formerly E17**, moved out of the open list 2026-08-10: it is a documented seam, not work anyone intends to do, and it was making the queue harder to read. Explored properly and dropped, because guest SMB is a fading, off-by-default macOS setting and a stored login is a trust cost for a small proprietary app; Folder Collections solved the same need over app-HTTP with no credential. Design record stays at HANDOFF §8, retired for Folder Collections in §17 | 2026-08-10 |
| D19 | Buffered / least-recently-shown eviction mode for the Library mirror. **Formerly E18**, moved out for the same reason as D18. A documented seam for a hypothetical next owner whose library exceeds their disk (a 300 GB 4K archive); the default full local mirror is what everyone actually runs, and this has never been built or needed. Not to be confused with the frame's Folder Collections cache, which is a shipped, separate, ephemeral session buffer. Design record stays at HANDOFF §9 | 2026-08-10 |

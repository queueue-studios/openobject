# OpenObject roadmap: the one list of open work

**Everything not yet done is one list, below.** Committed-but-undone work and optional
ideas sit together on purpose, so the list can be reviewed and dispositioned in one pass.
Where a row is already-committed work rather than a maybe, its note says so.

If work is open, it has a row here. If it is not here, it is either shipped or was decided
against, and the decision is in `HANDOFF.md` §20.

**This file holds no reasoning.** Every row points at the design record that does. That
split is deliberate: duplicated reasoning is what let four separate lists drift apart
(§17, the HANDOFF status line, `TVOS-APP-PLAN.md` phases, and scattered notes), so a row
here is one line plus a pointer, and it is cheap to keep honest.

**IDs are stable and never reused.** Talk about work by its ID. When a row ships, delete
the row and move its design record into §20; the ID retires with it. IDs were assigned
once, at creation on 2026-08-08.

**A `W` prefix means verify or observe, not build.** Those rows live in the same list, in
their own group, because a separate watch list is just a second list someone has to
remember to check. They are dispositioned the same way as everything else, and the bar for
keeping one is high: "wait and hope nothing happens" is not a row, it is a closed item.

The list after the main one is deliberately **not** a to-do: it records what was *decided
against*, so settled questions are not re-pitched. (An *unknowns* section held the frame's
RAM until it was confirmed on 2026-08-08; it is gone because nothing is unknown.)

Last swept: 2026-08-08.

---

## Enhancements: the one list to disposition

Size is a rough sense of the job, not a promise.

### The apps (iPad, iPhone, Apple TV)

| ID | Item | Design record | Notes |
|----|------|---------------|-------|
| E1 | Connected Collections on the iPad/iPhone app via `WKWebView`, plus the skip mechanism and the "Chrome Only" pill | HANDOFF §17 "Connected Collections on the viewer apps" | Large. **Gated:** do not open `ipad-app` until the submitted iOS build is approved. Two checks first: inkField untested, iPhone untested |
| E2 | Golden Lining as a pre-rendered looping video, a per-piece WebKit fallback | HANDOFF §17 "Golden Lining as a pre-rendered video" | Provisionally retired. Closes for good when E1's two checks pass |
| E3 | Offline / portable playback: the **iPad** holds its own art and keeps playing with no network. **Wanted, to pursue later** (Matt, 2026-08-08). iPad only, permanently: the Apple TV variant is closed by tvOS storage limits (D14) | HANDOFF §17 "Offline / portable playback"; `TVOS-APP-PLAN.md` §9 | Medium. Needs a persistent store, a "Download for offline" choice, the manifest persisted, and an offline launch path |
| E6 | Retro Arcade easter egg on tvOS / iPad. `arcade.js` is dependency-free canvas 2D and maps onto SpriteKit or SwiftUI Canvas; a Siri Remote D-pad is a better trigger than a keyboard | `TVOS-APP-PLAN.md` §5 | Medium. Post-v1 by choice |
| E19 | Release tooling for the App Store apps: teach `release.sh` to bump `tv-app/` and `ipad-app/project.yml` (or decide deliberately that the shells track their own version line), **and tag each App Store submission** (e.g. `tvos-1.6.2-submitted`) | memory: version-bump-release-workflow | Small. Formerly W5, reclassified 2026-08-08. Today the shells sit at 1.6.2 behind the platform at 1.7.2, and **no tag marks a submitted build**, so "what changed since the binary in review" needs someone to remember which commit did the bump (`a2dc043`) rather than being a one-line query |

### The frame

| ID | Item | Design record | Notes |
|----|------|---------------|-------|
| E8 | Wi-Fi onboarding: an `OpenObject-Setup` AP plus captive page, folding into the existing Network card. **Stages 1-2 done 2026-08-08** (the frame's Wi-Fi is on NetworkManager, and `install.sh` no longer carries a handoff that could never succeed); **stage 3, setup mode itself, is what remains** | HANDOFF §11; §20 2026-08-08; the original XXL's own flow, which Matt captured in screenshots, is the reference | Large. Surfaces only when the frame cannot connect (Matt, 2026-08-08). No QR codes: the network name and password in plain text, as the original did. Old credentials are never deleted, so a returning network just works |

### The Mac app

| ID | Item | Design record | Notes |
|----|------|---------------|-------|
| E11 | Host-list preface copy to clarify and de-jargon, aligning with the tvOS "OpenObject on your network" wording | memory: mac-app-ui-refinements-deferred | Small copy pass |
| E12 | Auto Display: an "art on every display" option for a gallery wall, instead of art on the main screen and the rest black | HANDOFF §20 2026-08-06 Auto Display record | Medium. Explicitly not the default |
| E13 | A native help surface in the app, or a Help button in the Settings pane that opens the control panel's Help. Today a Mac-only setting is explained on a different surface from where it lives | same | Medium. Trigger: when a second Mac-only setting appears |
| E14 | Move the Settings window to tabs | same | Small. Trigger: at five or six settings, not before |

### Docs and site

| ID | Item | Design record | Notes |
|----|------|---------------|-------|
| E15 | Owner-facing docs for the two App Store apps: the Setup Guide has no Apple TV or iPad section, and the Help card should carry the short version | `TVOS-APP-PLAN.md` §14 Phase F; HANDOFF §16 lockstep rule | Medium, needs Matt's voice. **Committed**, and the §16 lockstep rule already requires it |
| E16 | Post-approval site pass: iPad is still "coming soon" in three places on the home page (device chip, header status line, Display cell) and the Apple TV page still says iPad "follows" | `site/`; recipe in HANDOFF §15 | Small. **Committed**, once iOS is approved |

### Seams (built as interfaces, never filled in)

| ID | Item | Design record | Notes |
|----|------|---------------|-------|
| E17 | SMB pull as a source | HANDOFF §8; retired for Folder Collections in §17 | Optional seam, never built |
| E18 | Buffered / least-recently-shown eviction mode for the Library mirror | HANDOFF §9 | Documented seam, off by default |

### Checks and watch items

Verify or observe, not build. No action needed unless a check comes back wrong or a
symptom recurs.

| ID | Item | Design record | Notes |
|----|------|---------------|-------|
| W3 | Frame-only: switching Display Source from a folder back to the Library once made the frame's `display.js` go fully black. Never reproduced, and the native Apple TV handled the same switch fine | memory: tvos-app-plan-execution (2026-07-30) | Repro path: Mac Chrome at `http://openobject.local/display` with DevTools open during the switch |

## Pending device verification

Changes that are built and simulator-verified but have not been seen on the real hardware they
affect. **A row is added in the same commit as the change**, so it cannot be forgotten later, and
cleared when the check is done (or when the build carrying it ships). This is the pre-submission
checklist: the tag from E19 says what changed, this says what to look at.

| Device | What to check | Landed |
|--------|---------------|--------|
| Frame (fresh install) | The `install.sh` Wi-Fi handoff now delegates to `nm-handoff.sh` with the guard off. The retrofit path is device-proven, but the fresh-install path cannot be exercised without installing a new frame, which nobody can currently do | `36b6ffa`, 2026-08-08 |
| Apple TV | The per-Host row icon in the picker now matches its label size. Confirm on the real Apple TV, since that is where the undersized icon was noticed; the simulator before/after only proves the change took effect | `8adbbbe`, 2026-08-08 |

## Closed: decided against, or not worth tracking

Settled. Do not re-pitch without new information; if the answer changes, say what changed. Rows that were dropped rather than rejected are here for the same reason: so a later sweep of §20 and the memory files cannot quietly resurrect them as new items.

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

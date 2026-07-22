# OpenObject Apple TV App: Plan and Architecture Direction

> **Document type:** Execution plan. Nothing built yet.
> **Status (2026-07-20):** drafted and agreed in discussion. No code, no Xcode target,
> no App Store record yet.
>
> **Relationship to the spec:** `HANDOFF.md` stays the authoritative engineering spec
> for shipped behavior. This file is the plan; as pieces ship, the relevant HANDOFF
> sections (and the Setup Guide) are updated in the same change, and this file is
> trimmed or retired.
>
> **Supersedes:** `MAC-APP-PLAN.md` §8, which sketched the Apple TV app as browsing
> Bonjour and then rendering "that Host's `/display`". That is not possible (§2). The
> discovery half of §8 is correct and still stands; the rendering half is replaced by
> this document.

---

## 1. Why this exists

OpenObject has three surfaces today: the XXL frame (Debian kiosk), the Mac app, and the
web control panel. All three render art the same way, because all three are a web page.
The Apple TV is the fourth surface and the first one that cannot be.

The goal is deliberately narrow: **an Apple TV becomes a display for an OpenObject Host
on the same network.** It finds Hosts, the owner picks one, and from then on the rotation
curated in the existing control panel plays on the TV. Low function, high value.

It is also the project's first App Store submission, which brings review constraints the
Developer ID path never had (§12).

---

## 2. The correction: tvOS has no web view

tvOS ships no `WKWebView`, no `UIWebView`, and no `SFSafariViewController`. This is a
deliberate Apple exclusion dating to tvOS 1 and still true today. The only Apple TV
"browsers" that exist use private API and cannot ship on the App Store.

Two consequences follow, and they shape everything else:

1. **The app cannot wrap `/display`.** It must be a **native reimplementation of the
   Display role**: SwiftUI and AVFoundation rendering directly against the Host's API.
2. **Connected Collections cannot render on tvOS.** Every one of the 13 collections is an
   HTML page whose JavaScript must *execute* to produce the art: p5.js, three.js, canvas
   generators, loaded in an iframe at `/collections/<slug>/index.html`
   (`player/public/display.js`). They are programs, not files.

**This is not a fidelity problem, and it is not the Golden Lining problem.** Golden
Lining is separately broken on WebKit (HANDOFF §20, 2026-06-30); that is a different
issue and it is not the reason for this decision. There is simply no engine on tvOS that
can execute a web page. No decoder can be added and no library can be linked. The only
native path would be reimplementing each artist's program in Swift, which is absurd on
its face and would violate artistic fidelity even if it were practical.

### Note for later: pre-rendering Connected pieces

Recorded so it is not re-derived. There is a real path to Connected art on tvOS that does
not require a web view: **the Host pre-renders a piece to a seamless looping video**, and
the app plays the video like any other clip. The pipeline already exists in the project
(headless Chrome via CDP plus ffmpeg, used for the social demo loops), and the principle
is already on the record: the platform owes the artist's visual result, not the literal
code.

Not v1. The costs are real: live and on-chain pieces (Perfect Everything, Pendulum, the
time-of-day behavior in Lost in Moffat County) would go stale, pieces with owner controls
would need re-rendering on every change, and the Host would need Chrome and ffmpeg
present. But it is the answer if Connected art on the TV ever becomes important, and it
is a better answer than any native reimplementation.

### Why this also settles the iPad question

iPadOS *does* have `WKWebView`, so an iPad app could in principle render Connected art in
a web view. It should not, for a reason already on the record: `MAC-APP-PLAN.md` §5 locks
"**drive real Google Chrome**" for the Mac display precisely *because* an in-app
`WKWebView` is WebKit, the engine that tile-corrupts Golden Lining and other pieces. On
iPad there is no escape hatch, because every browser engine on iOS and iPadOS is WebKit
underneath. There is no Chrome to drive.

So the iPad's web view path would deliver Connected art at a fidelity the project has
already formally rejected. The parity goal (iPad and Apple TV feeling like the same app)
and the fidelity-honest choice turn out to be the same decision: **both apps are native,
and neither renders Connected art.**

---

## 3. The mental model: a fourth surface, Display role only

Per `MAC-APP-PLAN.md` §2, OpenObject has one engine and three roles. The Apple TV app
takes exactly one of them.

- **Host role: never.** The app does not run a server, own a Library, or store art. It
  ships with no content of its own at all. Art belongs to the Host; a viewer that carries
  its own art is a category error. (A bounded media cache is not ownership, §9.)
- **Display role: yes, natively.** It renders exactly one Host's rotation, full screen,
  zero chrome, following that Host's duration, order, pin, and sleep state.
- **Control role: no.** Curation stays in the web control panel, on a phone or computer.
  The app has settings (which Host, mute) and nothing else. It is not a remote.

The one screen the app owns that no other surface has is the **Host picker**. That is
chrome-legal territory; the art stage never is.

---

## 4. Locked decisions (agreed 2026-07-20)

- **The apps are free.** No subscription, no in-app purchase, no StoreKit. Platform
  monetization will be through licensing or sale of the platform itself, not from users.
- **Connected Collections are unsupported on tvOS, and are skipped, not removed.** The
  owner never has to curate a separate rotation. A rotation containing Connected pieces
  plays its compatible pieces on the TV and its full set everywhere else.
- **Animated GIF and animated WebP are in scope for v1**, not a stretch goal. An art
  player that freezes animation on frame one misrepresents itself, and "never freeze on
  frame 1" is already a project rule. See §6.
- **SVG and WebM are declined, with reasons** (§6). Neither is impossible; both cost more
  than they return.
- **The capability filter lives in the app, not the server.** The app decides what it can
  render. Rationale in §11.
- **A rotation with nothing renderable shows the existing splash screen**, unchanged and
  with no added explanation. Same screen as an empty rotation, same words ("add art
  at ..."). The stage stays clean; the "why" lives in Help and the Setup Guide.
- **The WebKit reason is stated plainly in the docs**, as a deliberate exception to the
  no-jargon rule. Owners should read it as a technical impossibility, not a product
  choice. Factual and brief, not apologetic.
- **Audio is supported, and every display owns its own mute** (§10). This amends the
  muted-always v1 rule.
- **The user-facing word is "Host", not "server".** Consistency outweighs picking the
  friendlier word in isolation: the Mac app already says Host, and HANDOFF's role
  vocabulary is Host/Display/Control, so a second name for one concept across two apps the
  same owner uses would cost more than it gains. "Server" also carries a legacy IT
  connotation. Capitalized in UI copy, so it reads as a defined thing rather than the
  everyday word.
- **One repository, one version.** `tv-app/` joins the existing shells; the version stays
  sourced from `player/package.json` per `MAC-APP-PLAN.md` §3.
- **Apple TV ships first, iPad second, on a shared core.** Rationale in §14.
- **The app's source stays public**, like the rest of the repo. With the apps free there
  is nothing to protect: anyone rebuilding it from source costs the project nothing.

---

## 5. Scope

**In:**
- Bonjour discovery of `_openobject._tcp` Hosts on the LAN.
- A Host picker listing what was found, by name.
- **Manual entry of a Host address**, for when Bonjour fails. A hedge against the known
  mDNS fragility on Matt's network, and the mechanism that makes App Store review
  workable (§12).
- A remembered default Host, so the app opens straight to art on later launches.
- A manual rescan.
- Native rendering of the Host's rotation: duration, Sequence/Shuffle, Pin, Fit/Fill,
  crossfade, and live folding-in of changes without restarting the loop.
- **Folder Collections.** Confirmed to need no special handling: `folders.itemsFor()`
  returns items with the same shape as Library items (`id / filename / format / kind /
  fit / src`), and the Host does all folder resolution before responding. The app cannot
  tell the difference. Expected to work as-is; confirm during Phase C.
- The idle/splash screen, matching the web display.
- The Sleep Hours / Blank state, matching the web display.
- Defeating the tvOS screen saver while art is playing.
- Audio with a mute toggle (§10).

**Out of v1:**
- Hosting, uploading, deleting, or curating anything. Permanently out, not deferred.
- Connected Collections, SVG, WebM (§6).
- **The Retro Arcade easter egg.** Deferred, not impossible. `player/public/arcade.js` is
  469 lines of dependency-free canvas 2D (`fillRect` sprites, a hand-authored 5x7 bitmap
  font, pure game logic), which maps cleanly onto SpriteKit or SwiftUI Canvas. It is
  arguably the most portable file in the repo. There is also a nice fit in the input: the
  trigger is a game-controller code, and entering it on a Siri Remote D-pad is more
  authentic than on a keyboard. Kept out of v1 only because it would compete for attention
  with the rendering path.
- Any Host-side power, update, or network function.

---

## 6. Format support on tvOS

| Format | On tvOS | Notes |
|---|---|---|
| JPEG, PNG | Yes | Straightforward. |
| GIF, animated | **Yes, v1** | ImageIO decodes frames and per-frame delays; a `CADisplayLink` drives them. Well-trodden, on the order of a few hundred lines. |
| WebP, static and animated | **Yes, v1** | ImageIO has decoded WebP since tvOS 14. Same frame path as GIF. No third-party dependency, no licensing question. |
| AVIF, still | Yes | Decode supported since tvOS 16. |
| AVIF, animated | **Verify** | AVIS sequence support in ImageIO is less certain than still AVIF. The rarest of the three animated formats by a wide margin. Confirm during Phase C. |
| MP4, MOV | Yes | AVPlayer, H.264/HEVC. |
| SVG | **Declined** | See below. |
| WebM | **Declined** | See below. |

### Why SVG is declined

Not impossible. Static SVG renders through a third-party Swift library (SVGKit,
PocketSVG and similar convert paths to CGPath). What none of them do is run SMIL or CSS
animation, which is explicitly part of how this project defines SVG support
(`player/src/formats.js`: "SMIL/CSS animation keeps playing"). So tvOS SVG would be
static-only, which is a silent fidelity gap rather than a clean win: an animated SVG would
appear frozen, which is the exact failure the "never freeze on frame 1" rule exists to
prevent. A system SVG path exists via private API and is off the table for the App Store.

### Why WebM is declined

Also not impossible. WebM decodes through TVVLCKit or an FFmpeg build, and Apple TV 4K
has VP9 hardware decode. **The blocker is licensing, not capability.** Both are LGPL, and
LGPL inside an App Store binary is genuinely fraught: VLC was pulled from the App Store in
2011 over this and returned only after relicensing. Even with the apps free (§4), the
repository is proprietary and all rights are reserved, so linking LGPL video libraries is
a legal question rather than an engineering one. Combined with WebM being the rarest of
the nine supported formats in real art libraries, it is not worth the exposure.

Both declines are **skips, not errors**: an SVG or WebM in the rotation is passed over on
the TV exactly like a Connected piece, and plays normally everywhere else.

---

## 7. Repository topology

One repository, one engine, a new shell alongside the existing ones.

```
player/         # shared engine, single source of truth (unchanged)
installer/      # XXL / Debian kiosk packaging (unchanged)
mac-app/        # native macOS shell, bundles + launches the engine (unchanged)
display-core/   # NEW: Swift package implementing the Display role natively
tv-app/         # NEW: tvOS app, thin UI over display-core
ipad-app/       # LATER: iPadOS app, thin UI over the same core
docs/
```

`display-core/` is named for the role it implements (`MAC-APP-PLAN.md` §2), and it is
what makes "the iPad app feels like the Apple TV app" true in code rather than in
intention. It owns discovery, the Host model and default-Host setting, the `/api/display`
client, the capability filter, the rotation engine (§8), and the media pipeline (§9). Each
app target is meant to be little more than screens and input handling.

`mac-app/` does **not** adopt it. That shell deliberately drives real Chrome for art
fidelity (`MAC-APP-PLAN.md` §5) and should keep doing so.

---

## 8. The rotation engine moves into a shared core

`player/public/display.js` is roughly 300 lines and is not a thin file. It holds the
timing loop, the Sequence/Shuffle bag (each piece once before reshuffling), the Pin
override, the crossfade between two stacked layers, Fit/Fill, the sleep state with its
slow anti-burn-in pixel drift, and the logic that folds library and settings changes into
a running rotation without restarting it (a 5 second poll of `/api/display`).

That behavior is the product. Porting it to Swift once, into `display-core/`, is what
keeps the TV and the iPad identical to each other and faithful to the frame. Porting it
twice, or approximating it, is how the surfaces drift apart.

Two details from the API worth recording, because they are easy to miss:

- **A pinned piece returns alone.** `/api/display` responds with `items: [pinned]` and
  nothing else (`player/server.js`). If the pinned piece is Connected, the app receives a
  one item list it cannot render and has no rotation to fall back to. It shows the splash
  screen, per §4. It does **not** silently substitute other art, because quietly ignoring a
  deliberate pin is worse than a blank screen the owner can reason about.
- **`kind` and `format` are already on every item**, so the capability filter needs no API
  change.

---

## 9. Media loading, buffering, and memory

The app fetches each piece from the Host over HTTP. On a LAN that is fast, but tvOS is
memory-constrained and kills hungry apps without ceremony, so this needs design rather
than a naive `URLSession` call per item.

**Large stills are the sneaky risk.** File size is not the problem; decoded size is. A
15MB image (the Tiles Static mode is roughly that) becomes a bitmap of several tens of
megabytes resident once decoded at panel resolution. Decoding must be bounded and sized
to the display, not to the source.

**Animated frames are the real risk.** Decoding a long GIF or WebP fully into memory will
crash the app. The pipeline needs **decode-on-demand with a small rolling frame buffer**,
which is the problem `FLAnimatedImage` solved on iOS and the reference for how to do it.
This is the part of §6's animated-format support that carries the actual difficulty, and
it is why the work is "a few hundred lines" rather than a dozen.

**Video is the easy case.** AVPlayer streams and manages its own buffering. Nothing to
build.

**Crossfade requires lookahead.** The next piece has to be decoded and ready before the
current one ends, so the pipeline keeps a one-item prefetch running ahead of the rotation.

**Caching.** Re-downloading every piece on every rotation pass is wasteful and adds
latency to each transition. A **bounded, purge-tolerant disk cache in `Library/Caches`**
solves it. tvOS reserves the right to evict that directory, so the cache must treat a miss
as normal rather than as an error. There is precedent to follow in the project rather than
a new concept: `player/src/folder-cache.js` already implements a bounded ephemeral media
cache with `usage()` and `clear()`. A cache is not ownership, so this does not conflict
with §3.

---

## 10. Audio (an amendment to a v1 decision)

The original v1 rule was "**muted, always**", chosen when the speakerless XXL frame was
the only target, so the decision cost nothing. Once the Mac became the primary surface,
and now a TV, suppressing audio is a real loss.

**That rule has already been partly retired, ahead of this plan.** As of 2026-07-20
(v1.5.0, HANDOFF §12) the shipped position is **uploaded video muted, Connected pieces
per-collection**: *The Bloom* carries its own **Music** control, default On, because its
soundtrack drives what the piece renders. Two facts came out of that work and are load
bearing here:

- **Both Chrome launchers already pass `--autoplay-policy=no-user-gesture-required`**
  (`mac-app/Sources/DisplayController.swift` since 2026-07-02,
  `installer/kiosk/chromium-kiosk.sh` since 2026-06-14). **This work is done.** Do not
  re-add it.
- **The XXL frame opens no audio output at all**, verified on the real device: an
  HDA-Intel card is present, but every playback substream stays closed. Audio is inert on
  the frame regardless of settings, so there is nothing to verify there.

**What remains: art with audio plays its audio, and every display owns its own mute.** In
practice this matters most for a **pinned video**, which is the case actually expected in
use, and which is still muted at the element today.

The abrupt cut when a rotation advances mid-audio is accepted as physics, not a bug: a
clip cut at the duration cuts its sound the same way it cuts its picture.

### Where mute lives

Not a Host-wide default with per-app overrides. That invents a precedence relationship
nobody needs and puts the setting in three places once device volume is counted. Instead:

**Each display decides whether it makes noise.** The web display's control lives in the
control panel, because a browser page at `/display` has no UI to put it in. The app's
control lives in the app, because it can have one. No inheritance, no precedence.

Note that a *per-collection* control already exists (The Bloom's Music). A display-level
mute sits above it and is not a replacement: the collection control says whether a piece
is scored at all, the display control says whether this screen makes noise. Reconcile the
two when Phase A runs rather than assuming they collide.

This is also the conventional split for ambient media apps: **device volume controls how
loud everything is; the app controls whether this content makes sound at all.** Muting art
in-app so the TV does not have to be re-leveled is the real use case, and it is why an
app-level mute is not redundant with the hardware volume control.

### Work outside the app

The browser-launcher half is already done (above). What is left is the page itself, and
getting it wrong would mean a video with sound does not play **at all** rather than
playing silently. **Chrome blocks unmuted autoplay by default**: `video.play()` returns a
rejected promise and nothing starts. Deleting `el.muted = true`
(`player/public/display.js`) and changing nothing else produces exactly that failure on
any browser launched without the flag.

So the page needs a **fallback for the path we do not launch.** Someone opening
`http://localhost:3000/display` in their own browser has no flag, and the README tells
people to do exactly that. The display attempts unmuted playback, catches a rejected
`play()`, and retries muted. **Art never stops; at worst it is silent on that one path.**

The Bloom hit this same wall and solved it differently, by starting its track on the
viewer's first click (`player/src/collections.js`). That works for a piece a person is
sitting in front of; it is not available to a passive rotation, which is why video needs
the retry instead.

Verified on a real Mac before it ships. Nothing to verify on the frame, which has no
audio output.

Separately and out of scope here: several Connected Collections had audio stripped when
their bundles were built, which in hindsight was too aggressive. Matt will audit those in a
separate session and rebuild the affected pieces. Expected to be a small number.

---

## 11. Compatibility across versions

The Host updates over the air the moment a change is pushed. The App Store app updates
only after review, and then whenever each device gets around to it. **An Apple TV in the
field will routinely be running a version behind the Host it is talking to**, and
occasionally ahead of one.

Two rules follow, and they are why the capability filter is client side:

- **The app must work against any Host version**, including Hosts that predate the app
  entirely. It therefore filters on what it can render, never on a flag the server might
  not send. This also means SVG and WebM are handled by the same code with no server
  involvement.
- **The Host must assume nothing about the app.** No tvOS-specific endpoint, no negotiated
  capability handshake, no per-client filtering. `/api/display` stays one response for
  every Display.

---

## 12. App Store and review

The apps are **free** (§4). No StoreKit, no in-app purchase, no subscription group,
nothing to configure on the commerce side. What remains is distribution.

- **One App Store record covering both platforms**, tvOS now and iPadOS later, so the pair
  reads as one product with one listing and one name. That still makes the bundle
  identifier a decision to take now rather than at iPad time, for listing coherence rather
  than for purchase entitlement.
- **Signing:** the Queueue Studios LLC account, the same identity as the Mac app.
- **Apple Developer Program membership** is required to ship at all, free app or not.

**Review risk.** Free does not exempt an app from Guideline 2.1 (app completeness).
`MAC-APP-PLAN.md` §8 already recorded the research: a LAN client app is not rejected
merely because reviewers have no Host to find, but an app showing only a "nothing found"
dead end can be flagged.

That note listed bundled sample art as a mitigation. **It is not the right one here.** The
app is a viewer; it owns no art (§3), and bundled art would not demonstrate the feature
under review anyway, because a reviewer's Apple TV cannot Bonjour-discover anything beyond
its own network. The mitigations that actually work:

- **Manual Host entry** (§5), so a reviewer can reach a Host that is not on their LAN.
- **A temporary reachable Host** stood up for the review window, with its address in the
  reviewer notes.
- **States that read as working rather than broken**, which is a design rule broad enough
  to have its own section (§13).

Nothing about this puts content inside the app. Owners add compatible pieces to their
rotation on the Host, which is the same thing they already do for the frame and the Mac.

---

## 13. State design: never look broken

The app spends real time in states where nothing is on screen: scanning, finding nothing,
connecting, and playing a rotation with nothing it can render. Every one of those has to
read as **working and waiting**, never as failed.

This matters twice over. It is what keeps an App Store reviewer with no Host on their
network from concluding the app is non-functional (§12), and it is what an owner sees when
their Mac is asleep or mDNS is misbehaving, which on this project's history is not rare.
The reviewer case and the stranded-owner case want the same design, which is why this is
worth building properly rather than staging for review.

**The rule: only a genuine error uses error language and error styling.** Everything else
is a waiting state or a setup state, phrased in terms of what will appear rather than what
is missing.

| State | Reads as | Wording |
|---|---|---|
| Scanning on launch | active | "Looking for OpenObject Hosts..." |
| No Hosts found | waiting, not failed | "OpenObject Hosts on your network will appear here." |
| Hosts found | a named list | (the picker) |
| Connecting | active, brief | "Connecting to \<name>..." |
| Nothing renderable in the rotation | the existing splash (§4) | "add art at ..." |
| Host disappeared mid-playback | calm, not alarming | open item, §16 |
| A typed address did not answer | **a real error, stated plainly** | "No OpenObject Host answered at that address." |

Two implementation notes carry most of the effect:

- **The scanning state needs a floor.** Bonjour takes a beat to answer, and a picker that
  flashes straight to "nothing found" reads as broken even when a Host is about to appear.
  Hold the looking state briefly rather than resolving instantly to empty.
- **The empty state must offer an action**, which is manual Host entry (§5). A screen with
  an explanation and no affordance is still a dead end, and a dead end is what gets flagged
  under Guideline 2.1. A reviewer who can type an address can evaluate the app.

This is a consistency point as much as a new idea. The frame already says "Looking for
your Mac..." while it waits on a Folder Collection Host, and the display's idle screen
already tells the owner where to go instead of reporting that the rotation is empty. The
app should sound like the rest of OpenObject.

**Restraint still applies.** One clear line and one obvious action per state, not a
paragraph of instructions. The house style is to fix behavior so it matches expectation
rather than to label it, which is why the control panel has no hint text.

---

## 14. Execution phases

Roughly in order. Phase A carries no app risk and benefits the existing surfaces, so it
can land first and independently.

### Phase A: Engine seams (shared, benefits the Mac and the frame too)
- **Audio**, per §10: make uploaded video's `muted` conditional instead of hard-coded, add
  the page-level catch-and-retry-muted fallback, and add the control panel's mute setting
  for the web display. **The Chrome autoplay flags are already in both launchers; do not
  re-add them.** Ships with CLAUDE.md, HANDOFF §12, and Setup Guide updates, since it
  changes user-facing behavior.
- **Splash address fix.** The idle screen picks `addresses[0]` from every non-internal
  IPv4 interface (`player/server.js` `lanAddresses()`, consumed at `display.js`), which is
  enumeration order, not reachability. On a multi-homed machine it can display an address
  the viewer cannot reach, and VPN tunnels and virtualization bridges qualify for the list
  too. The control panel already renders all addresses correctly; the splash is the
  inconsistent one. Fix: filter to real LAN interfaces and prefer the default route. No UI
  change. **Pre-existing bug, worth fixing on its own regardless of this project.**

### Phase B: `display-core/`
The shared Swift package: discovery, Host model, default Host, `/api/display` client,
capability filter, rotation engine (§8), media pipeline and cache (§9). Testable without
any UI.

### Phase C: `tv-app/`
The tvOS target: Host picker, manual Host entry, art stage, settings, idle timer, audio
session, splash and sleep states, and the full set of waiting and setup states from §13.
Confirms Folder Collections (§5) and settles animated AVIF (§6).

### Phase D: Branding and assets
Its own phase, run when the app is functional. tvOS needs a layered parallax app icon
(rectangular, not square), a Top Shelf image, and a launch screen. Matt authors these in
Photoshop from the OPEN/OBJECT wordmark; he gets a written brief with the exact slots,
sizes, and layer structure at the start of this phase, not before.

### Phase E: Public site pages, then App Store submission
App Store Connect requires a **privacy policy URL** and a **support URL** for every app,
free ones included, and neither exists on openobject.io today. GitHub Pages serves any
static file structure, not just one landing page, so these are new files alongside
`site/index.html` published the same way (gh-pages re-publish, keeping the CNAME). App
Privacy declarations are expected to be a clean "Data Not Collected": the app talks only
to a Host on the owner's own network and has no analytics, no accounts, and no backend.

Then the submission itself: app record covering both platforms, reviewer notes, the
temporary review Host.

### Phase F: Docs (lockstep, HANDOFF §16)
HANDOFF gains the engineering record. The Setup Guide gains an Apple TV section, including
the plain statement of why Connected art does not appear there. The control panel Help card
gains the same explanation in shorter form.

### Phase G: iPad (later)
A second thin target on the same core. Explicitly not a web view (§2).

---

## 15. Guardrails

- **The XXL path is untouched.** Nothing here may regress the frame.
- **The engine is not forked.** Shared behavior lands in `player/`; platform behavior
  lands in that platform's shell.
- **The art stage stays zero chrome.** No badges, no overlays, no explanatory text on the
  stage, ever. Everything the app needs to tell the owner is said on the picker screen or
  in the docs.
- **The control panel stays casual and uncluttered.** No per-item "won't play on Apple TV"
  badges in the Library. The panel serves every display.
- **Art never touches the repo.**
- **Docs lockstep** (HANDOFF §16).
- **One version across the platform** (`MAC-APP-PLAN.md` §3).

---

## 16. Open items to settle during execution (not blocking the plan)

- Animated AVIF support in ImageIO (§6), settled at Phase C.
- Whether Folder Collections need any handling at all (§5), expected to be none, confirmed
  at Phase C.
- The bundle identifier, chosen with the iPad listing in mind (§12).
- Cache size ceiling and eviction policy (§9).
- Behavior when a Host disappears mid-playback: hold the last frame, splash, or return to
  the picker (§13).
- How the temporary review Host is stood up and reached (§12), settled at Phase E.
- Content and wording of the privacy and support pages (§14, Phase E).

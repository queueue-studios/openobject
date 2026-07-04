# OpenObject Mac App: Plan and Architecture Direction

> **Document type:** Execution plan — under active execution.
> **Status (updated 2026-07-03):**
> - **Phase A (engine seams) — DONE**, verified on hardware (Host/Display/Control roles,
>   Bonjour `_openobject._tcp` advertisement, `/api/identity`, same-origin Display target).
> - **Phase B (the `mac-app/` shell) — DONE**, verified on hardware: a native Swift app that
>   bundles Node + a copy of `player/`, runs a Host, discovers Hosts over Bonjour, offers a
>   first-run Access-a-Host vs Host-here choice, drives a real Chrome kiosk at the chosen
>   Host's `/display`, and has a window + app menu + menu-bar remote. Confirmed the Mac app
>   finds and can view/control the real XXL frame.
> - **Phase C — DONE.** The **signing/notarization pipeline is validated** (step 0
>   "smoke-test"): a signed, notarized, stapled build under the **Queueue Studios LLC**
>   Developer ID (`mac-app/scripts/sign-and-notarize.sh`). **Branding: DONE** (app icon,
>   menu-bar square-frame mark, and the in-app OPEN/OBJECT wordmark), and the deployment
>   target is now **macOS 15**. **Polish: per-Host renaming DONE** (a Name field in the control
>   panel's Network card writes `host_name` and re-advertises over Bonjour, so multiple frames
>   are distinguishable), plus **stale-Host pruning** (a reachability sweep hides Hosts that
>   vanished ungracefully), a **Dock-icon Settings pane** (Auto/Light/Dark, follows the system on
>   Auto), and **button-margin** polish. **Release infrastructure (C2/C3) DONE:** `build-dmg.sh`
>   (drag-to-Applications dmg, signed/notarized/stapled) and **Sparkle** (SPM, embedded, "Check for
>   Updates", `SUFeedURL` → openobject.io/appcast.xml, EdDSA key in Matt's keychain; `sign-and-notarize.sh`
>   signs Sparkle's nested helpers). **Release (C4): DONE — OpenObject 1.1.0 shipped** via
>   `release.sh`: a notarized `OpenObject-1.1.0.dmg` on the `v1.1.0` GitHub Release (authored by the
>   neutral `queueue-dev`, not `mattonchain`), with the Sparkle appcast live at openobject.io/appcast.xml.
> - **Phase D (docs) — NOW UNBLOCKED** (a real `.dmg` exists): write the Mac App guide, reposition the
>   docs so the no-frame Mac path is primary, and link the download.
>
> The authoritative, detailed build log is **`HANDOFF.md` §20** (newest first); read the
> 2026-07-03 and 2026-07-02 entries to resume cold.
> **Relationship to the spec:** `HANDOFF.md` stays the authoritative engineering
> spec for shipped behavior. This file is the plan; as pieces ship, the relevant
> HANDOFF sections (and the Setup Guide) are updated in the same change, and this
> file is trimmed or retired.

---

## 1. Why this exists

OpenObject started as an end-to-end kit to wipe an Infinite Objects XXL frame and
turn its MeLE mini PC into a self-hosted art player (Debian, Chromium kiosk,
systemd, over-the-air git self-update). That path is live and verified on the real
frame. Along the way the project also grew a second, now-primary audience: people
with **no frame** who want to run OpenObject on a **Mac**.

Today the Mac path is a developer-style install: download the repo, open Terminal,
`npm start`, point Chrome at `/display`. It works, but it is not a product a normal
person installs. This plan turns that path into a **proper signed Mac app** (a
notarized `.dmg`, drag to Applications), while leaving the XXL frame path exactly as
it is, and positions the architecture for a future tvOS companion app.

### Goals (in priority order)
1. **Do not disrupt the working XXL setup.** The frame keeps its Debian + kiosk +
   systemd + git-pull self-update, untouched.
2. **Keep the GitHub do-it-yourself path** for other XXL owners to revive their
   units from the repo and the Setup Guide.
3. **Ship a proper Mac app** that ordinary people install and run to host
   OpenObject on their Mac.
4. **Land a signed, notarized `.dmg`.** App Store is explicitly **not** a goal
   (see §8); the notarized Developer ID `.dmg` is the target.

### Non-goals for this plan
- The **tvOS companion app** is not built here. This plan only puts the
  architecture in place (network discovery, a clean Host/Display split) so tvOS is
  a natural next step, not a rework.
- **App Store submission** of the Mac app. Not pursued; the design is free to use
  mechanisms the App Store sandbox forbids (a bundled server, Sparkle updates).

---

## 2. The mental model: one engine, three roles

The confusion about "are the packages combined?" clears up once the frame's two
jobs are named separately. OpenObject has one shared engine and three roles:

- **Host role.** Owns a Library and a Rotation, serves the API and `/display`. The
  always-on brain. The XXL is always a Host; a Mac can optionally be a Host.
- **Display role.** Renders exactly one Host's stage, full screen, zero chrome. The
  XXL kiosk is a Display; a Mac window is a Display; a future Apple TV is a Display.
- **Control role.** The web control panel. Already Host-agnostic: any browser on the
  network can drive any Host.

The **single engine** (`player/`) is the source of truth for all three and runs
byte-for-byte the same on the XXL and on a Mac. What differs between configurations
is only the **packaging shell** around that engine and the **update mechanism**, both
thin and well understood.

A future Apple TV app is simply a **Display-role shell that points at a Host it
found on the network**. The Mac app is a native shell that can be **Host and/or
Display**. Framing the work around these three roles is the whole architecture move.

---

## 3. Repository topology: one engine, thin packaging shells (not two forks)

We keep **one repository and one engine**. We do not maintain two versions of the
solution. What we add is a new packaging shell alongside the existing one.

```
player/       # shared engine, the single source of truth (existing, unchanged in spirit)
installer/    # XXL / Debian kiosk packaging: install.sh, kiosk scripts, systemd units (existing)
mac-app/      # NEW: native macOS shell that bundles + launches the player engine
docs/         # split by audience (frame guide, Mac app guide, this plan, HANDOFF)
```

- `player/` is never forked. Both the frame and the Mac app run the same code.
- `installer/` is the frame-only shell and is not touched by this work.
- `mac-app/` is the new shell. It bundles a Node runtime and a copy of `player/`,
  launches the server, discovers Hosts on the network, and drives the display.

**Versioning stays unified.** `player/package.json` `version` is the single source of
truth. A Mac release wraps that exact engine version; the GitHub Release tag and the
Sparkle appcast advertise the same number. The XXL and the Mac cite the same version
even though they are delivered and updated differently.

---

## 4. Update model (this is the key difference between the two shells)

The frame updates by `git pull` because it is a plain, mutable git checkout on a full
Linux box. **A signed Mac `.app` bundle cannot work that way:** notarization seals the
bundle contents, so pulling new files into it would break the signature and Gatekeeper.
The engine therefore ships *inside* each signed Mac build, and to update it you ship a
whole new signed build.

| Configuration | Install | Update mechanism |
|---|---|---|
| **XXL frame** | flash Debian, run `installer/install.sh` | `git pull` of the repo checkout + supervised restart (unchanged) |
| **Mac `.dmg`** | drag the app to Applications | **Sparkle**: the app checks an appcast, downloads a newer notarized build, replaces itself atomically |
| **App Store** (not pursued) | store | store (Sparkle removed from that build) |

**Sparkle** is the standard framework for self-updating Mac apps distributed outside
the App Store. It checks an **appcast** (a small XML feed), verifies a cryptographic
signature on the new build, and swaps the app in place. It is the "Check for Updates"
menu item familiar from many Mac apps. Because App Store is not a goal, **Sparkle is
the update mechanism from day one and permanently**; there is no awkward interim. The
first-run install is the `.dmg` (drag to Applications); every update after is Sparkle.

The appcast and the `.dmg` assets live on **GitHub Releases**, matching the existing
release workflow. `openobject.io` may link to the latest release but does not host the
feed.

---

## 5. Locked decisions (agreed 2026-07-01)

- **Target: notarized Developer ID `.dmg`.** Drag to Applications. App Store not
  pursued.
- **Signing identity:** Matt's new **LLC Developer ID** (being established). Nothing
  in this plan depends on it existing yet; it is needed at the signing/notarization
  step (Phase C).
- **Shell technology: native Swift app + bundled Node.** The Swift app manages the
  server, discovery, and control surface; a copy of `player/` runs under a bundled
  Node binary. Not Electron, not Tauri.
- **App presence: Both a Dock icon and a menu-bar item.** Discoverable as a normal
  app, plus a menu-bar item for quick start/stop, open control panel, open display.
- **Display engine: drive real Google Chrome.** The full-screen display runs in real
  Chrome (as the frame kiosk and the current Mac do), not in an in-app web view.
  **Reason:** an in-app `WKWebView` is Apple's WebKit, the same engine that
  tile-corrupts Golden Lining and other pieces on Safari (see HANDOFF §20,
  2026-06-30). Driving real Chrome keeps rendering identical to the frame and avoids
  those known art bugs. Trade-off accepted: the app expects Chrome installed and shows
  a separate full-screen Chrome window.
- **Updates: Sparkle, appcast on GitHub Releases.** See §4.
- **Discovery: Bonjour / mDNS at the engine level**, via a small cross-platform Node
  dependency so one code path serves both the XXL and the Mac. Service type
  `_openobject._tcp`. This is the seam that later enables the Apple TV app.
- **Node bundling: a plain bundled Node binary plus a copied `player/`.** No exotic
  single-executable packaging; consistent with the no-build-step, revivable ethos.
- **Versioning: unified**, sourced from `player/package.json` (see §3).

---

## 6. Execution phases

Worked roughly in order. Phase A quietly benefits the XXL too and carries no Mac-app
risk, so it can land first and independently. Each phase lands with HANDOFF and (where
user-facing) Setup Guide updates in the same change.

### Phase A: Engine seams (shared, benefits the XXL too)
Additive, off the playback path, safe for the frame.
- **A1.** Name the Host / Display / Control roles in the engine and docs (mostly
  vocabulary; the server is already the Host).
- **A2.** Have the **server advertise itself over Bonjour/mDNS** (`_openobject._tcp`)
  with a friendly name, port, version, and a stable id. On the frame this sits
  alongside the existing Avahi hostname; on the Mac the same code runs.
- **A3.** Add a small **identity / discovery** surface so a Display or Control client
  can list Hosts on the network and ask each "who are you?" (name, version, id).
- **A4.** Let the **Display role target a chosen Host** rather than assuming
  localhost, carefully, so the frame's localhost kiosk behavior is exactly preserved
  by default.

### Phase B: The Mac app shell (`mac-app/`)
- **B1.** Swift app skeleton with **both** a Dock presence and a menu-bar item;
  bundles the Node binary and a copy of `player/` at build time.
- **B2.** On launch, either spawn the server (Host role) or act as a viewer
  (Display / Control role), per the user's choice.
- **B3.** First-run onboarding: browse Bonjour; if a Host is found (for example an
  existing XXL), offer "display / control that one" versus "run my own here."
- **B4.** Display: drive a real Chrome window (kiosk / app mode) at the chosen Host's
  `/display`, full screen, zero chrome. Control panel opens in the default browser or
  a simple in-app window.
- **B5.** Menu-bar and menu UX: start/stop the server, open the control panel, open
  the display, show whether it is running as Host or Display and which server, quit.
- **B6.** Mac data location: `~/Library/Application Support/OpenObject/` for the
  library DB and uploads (the equivalent of `player/data/` and `uploads/`).

### Phase C: Signing, notarization, delivery
- **C1.** Codesign with the LLC Developer ID (the **Queueue Studios LLC** team, not the
  old Personal Team; both are signed into Xcode, so select deliberately); hardened
  runtime; entitlements for the bundled Node child process and the local server.
- **C2.** Notarize and staple; build the drag-to-Applications `.dmg`.
- **C3.** Integrate Sparkle: generate signing keys, publish the appcast, wire "Check
  for Updates."
- **C4.** Release workflow: tag, snapshot the engine into the app, sign, notarize,
  publish the `.dmg` and the appcast entry to the GitHub Release. Version flows from
  `player/package.json`.

### Phase D: Docs (kept in lockstep, HANDOFF §16)
- **D1.** HANDOFF §20 decision entry capturing this direction (written first when
  execution begins).
- **D2.** New user-facing **Mac App guide** (dead simple: drag to Applications, open).
- **D3.** Reframe docs by audience: the **Frame guide** (`SETUP-GUIDE.md`), the new
  **Mac App guide** as the hero for no-frame users, the DIY Terminal path
  (`MAC-DISPLAY-SETUP.md`) demoted to a developer appendix, tvOS as a future stub.
- **D4.** Setup Guide stays in lockstep with shipped behavior.
- **D5.** Add the **"viewing is not owning" positioning statement** (below) to the
  README, the Mac App guide (right where the owner is about to upload), and the
  homepage. It is a values statement, always true, so it is not gated on the app
  shipping (see the timing clocks in §7).

**Positioning statement (viewing is not owning).** A short, reassuring note that draws
the owning/using line honestly, so artists are met with the distinction rather than
surprised by it. Keep the voice consistent with the proprietary license (source public,
all rights reserved) and the White Walls framing. Draft copy:

> **On displaying art you love**
> Anyone can view digital art in a browser, download it, or take a screenshot. That has
> always been true, and it isn't what OpenObject changes. Viewing art and *using* art are
> different things.
> OpenObject is built to display art you own, or otherwise have the right to display, and
> it's intended for home use. If you display art in public, please make sure you have a
> license to do so. We intentionally avoided wallet connections and their complexity: the
> process is simply to save a local copy of your art and upload it to OpenObject to
> display it.

---

## 7. Docs and license timing (three clocks)

These three things answer to different clocks, so they are sequenced separately rather
than done together:

- **Positioning statement (§ D5): anytime.** It is a values statement, always true, and
  not gated on any shipped behavior. Land it in the README and homepage whenever docs
  are next touched, independent of the `.dmg` timeline.
- **LICENSE: changed 2026-07-03 (the monetization trigger fired).** As part of the
  LLC/org migration, and ahead of paid tvOS/iPad apps, the source license moved from
  PolyForm Noncommercial to **proprietary, all rights reserved** (source stays public,
  with a narrow grant to run it on your own display or frame). Shipping a notarized
  `.dmg` still does not require any further license change; compiled binaries can be
  distributed as-is. The one *new* license artifact the Mac app may still want is
  separate: a short **end-user note / EULA for the app itself** (shipped with the binary,
  required if the App Store is ever pursued), handled at Phase C/D, not a change to the
  repo `LICENSE`.
- **README, then homepage: gate on shipped reality.** Update the **README** to reposition
  around the Mac app when the `.dmg` actually exists and is downloadable (end of Phase C
  / start of Phase D); repositioning it to say "download the Mac app" before there is one
  would mislead the next owner. Update the **homepage (openobject.io) last**, after the
  README settles (matches the doc-overhaul sequence: new guide first, incremental docs,
  website last; the homepage update needs a gh-pages re-publish that keeps the CNAME).

---

## 8. The multi-Host / discovery story (and how it sets up Apple TV)

The most forward-looking part, and the reason Phase A matters even before the app.
Today the frame **fuses** Host and Display into one box. Splitting them, and making the
Host discoverable on the LAN, is what makes the Mac app's onboarding and the future
Apple TV app both fall out of the same primitive.

Concretely, when an XXL owner opens the Mac app:
- It **browses the network for OpenObject Hosts** (`_openobject._tcp`). It finds the
  existing XXL Host.
- It **asks what the Mac should be:**
  - *Use this Mac as a display / remote for the frame:* Display / Control role only, no
    competing server. A sensible default when a frame is found.
  - *Run this Mac as its own OpenObject player:* a second, independent Host with its own
    Library and Rotation. Multiple Hosts coexist fine; each just needs a unique Bonjour
    name.
- **The frame is never disturbed** either way. The Mac is additive.

The **Apple TV app** (future) is the same story with the role narrowed to Display: it
browses Bonjour, shows a **list of OpenObject servers found**, the user picks one, and
it renders that Host's `/display` and follows the rotation curated there. Selecting the
frame versus the Mac Host is just picking a different entry in that list.

### Note for later: tvOS App Store review without a server
Parked, but recorded so it is not re-derived: a LAN-client app will **not** be rejected
merely because reviewers cannot find a server on their test network, but an app that
shows only a "can't find a server" dead end can be flagged under Guideline 2.1 (app
completeness). The standard, cheap mitigation (used by Plex, Infuse, VLC's remote, and
similar) is a **graceful empty state plus a demo / sample mode** (bundled sample art so
the app is obviously functional) and clear onboarding, optionally reviewer notes
pointing at a reachable test server. Not built now; a non-issue when tvOS arrives.

---

## 9. Guardrails (what must not change)

- **The XXL path is untouched.** `installer/` and the git-pull self-update model stay
  exactly as they are. No change to this plan may regress the frame.
- **The engine is not forked.** All new behavior lands in `player/` (shared, additive)
  or in `mac-app/` (the new shell). If a change would only make sense on one platform,
  it belongs in that platform's shell, not in a fork of the engine.
- **Art never touches the repo** (HANDOFF §8, §15). Mac library data lives under
  `~/Library/Application Support/OpenObject/`, gitignored in spirit exactly as the
  frame's runtime data is.
- **Docs lockstep** (HANDOFF §16): any user-facing behavior that ships updates the
  Setup Guide (or the new Mac App guide) in the same change.
- **Repo is public but proprietary** (all rights reserved; source public, not open
  source, not licensed for reuse). The next-owner mission still drives design: owners may
  run it to revive their own frame.

---

## 10. Open items to settle during execution (not blocking the plan)

- Exact Chrome invocation for the display (kiosk vs app mode, choosing a monitor,
  behavior when Chrome is not installed).
- Default role choice UX when both a frame and "run my own" are possible (first-run
  wording; whether the choice is remembered).
- The specific cross-platform mDNS Node dependency, vetted for the frame's Debian and
  for macOS.
- Whether the control panel opens in the default browser or a minimal in-app window.
- Sparkle key management and appcast layout under the GitHub Releases workflow.

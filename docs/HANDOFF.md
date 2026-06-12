# OpenObject — Build & Handoff Specification

> **Document type:** Implementation spec for Claude Code.
> **Status:** Build in progress (Phase 0–1). The web app is built and tested on macOS first; hardware/Linux work (Phase 2) is deferred until bench access. See §20 for the decision log.
> **Local project root:** `/Users/mattlhx/Code/OpenObject`
> **GitHub repo:** Created **private** during development (2026-06-11); intended to go public later. Claude drives all git operations on Matt's approval.

---

## 1. What OpenObject is

OpenObject is replacement software for the **Infinite Objects XXL** digital art frame — a 26" **square (1:1)** display whose original "White Walls" software (an Android kiosk app that rendered on-chain NFT art) has become unreliable as the vendor went quiet and its backend decayed.

The XXL's display is driven by a small **fanless mini PC mounted on the back of the panel**. OpenObject wipes that mini PC and turns it into a clean, self-hosted local art frame: it displays local image and video files, is controlled entirely from a web page the owner opens in any browser, and depends on no external service.

**Two design commitments shape everything:**

1. **Self-contained on the player.** The mini PC is the always-on brain. The owner's Mac/phone are just places files come *from* and a browser to control it; the frame never depends on them to keep running.
2. **Revivable by the next owner.** This is meant to be a shareable kit so *other* stranded XXL owners can revive their units. Design decisions favor "anyone can follow the guide" over "convenient for the original builder only."

---

## 2. Hardware target

The mini PC is a **MeLE Quieter 3Q** (confirmed from the unit's label).

| Attribute | Value |
|---|---|
| Model | MeLE Quieter 3Q |
| CPU | Intel Celeron **N5100** (Jasper Lake), **x86-64** |
| RAM | 8 GB LPDDR4x _(typical config; confirm at bench)_ |
| Storage | 128 GB eMMC _(typical config; confirm exact free space at bench)_ |
| Expansion | microSD slot (pressure valve for larger libraries) |
| Networking | Onboard **Wi-Fi 5** + **Gigabit Ethernet** (RJ45) |
| Power | 12 V / 2 A barrel jack |
| FCC TX ID | PD99560D2 _(use to confirm Wi-Fi module / Linux driver at bench)_ |
| Serial | 8ICH4F310P530467 |
| MAC | 00CE39D53121 |

**Ports on the outward-facing edge:** 1× USB-A 3.0, 3.5 mm audio, microSD, 2× HDMI, 1× USB-C (DP-capable), 1× Gigabit Ethernet, barrel power.

**Critical hardware facts for the build:**

- This is a **normal x86 PC with a UEFI BIOS**, not an Android appliance. Infinite Objects installed Android-x86 and ran White Walls as a kiosk launcher — that is *why the original UI looks like Android* — but underneath it boots like any PC and will happily run Linux from a USB stick.
- The mini PC connects to the 26" panel via a captive **HDMI** lead (video) plus a **USB-C** lead (power and/or control). **This cabling is not touched.** OpenObject is a software reflash; the player↔panel wiring stays exactly as the vendor built it. After Linux is installed, video outputs over the same HDMI the panel already uses.
- When wall-mounted, only **one USB-A port is realistically free**, and the physical power button is hard to reach. Both constraints are solved in §4 and §10.

---

## 3. Operating system

**Lightweight Linux** (Debian-based minimal recommended; final choice at build time). Selection criteria:

- Recent-enough kernel that the **onboard Wi-Fi works out of the box** (verify the module via FCC ID / `lspci`/`lsusb` at bench; keep a known-good USB Wi-Fi dongle as the only fallback — it would ride in the hub).
- Can run **Chromium in kiosk mode** as the display surface (see §6).
- Can run a small local web server for the control panel and the display page.
- mDNS via Avahi so the panel is reachable at `http://openobject.local`.
- Samba available **only** if the optional SMB pull-source is enabled (see §8); not required for the default web-upload flow.

The OS image should boot directly into the OpenObject display with no desktop, login, or visible Linux chrome.

---

## 4. Access & reflash procedure (one-time bench/in-place session)

This is the procedure to convert a stock XXL to OpenObject. It is performed once. The unit can stay wall-mounted; the outward-facing port edge remains reachable.

> **⚠️ Caution — do NOT remove the two screws above the MeLE.** On the back of the XXL, the two screws on the bracket/plate directly **above** the MeLE mini PC retain captive nuts on the *inside* of the chassis. Loosening or removing them drops those nuts inside the unit, and recovering them requires a **near-full disassembly and reassembly** of the XXL. They are **not** part of this procedure — leave them alone.

**Access hardware** (the owner-supplied kit — exact models recorded in the Setup Guide, §16):
- Right-angle USB-A extension from the single free port out to a reachable spot, then a USB hub on the end (one port can't host both the installer stick and a keyboard).
- USB keyboard (a keyboard+touchpad combo on one dongle is ideal).
- USB flash drive (≥16 GB) for the Linux/OpenObject installer.
- External USB drive (≥128 GB; small USB SSD ideal) for the pre-wipe backup image.

**Procedure:**

1. **Connect** the hub to the free USB-A port; attach keyboard + installer flash drive.
2. **Enter the BIOS** at power-on (key is typically `DEL`, `ESC`, or `F7` — _confirm at bench and record_). The panel shows the BIOS screen over HDMI.
3. **Set boot order / boot menu** to boot from the USB flash drive.
4. **Enable "Auto Power On" / "AC Power On"** in the BIOS so the unit boots whenever it receives power — no button press needed afterward (see §10).
5. **Boot the live USB.**
6. **BACK UP FIRST — image the existing eMMC** to the external drive (full-disk image). This preserves the original White Walls + Android-x86 install in case the owner ever wants it back *while the vendor's servers still exist*. This is the clean, ADB-free way to capture it. **Do this before any wipe.**
7. **Install OpenObject** (Linux + the OpenObject stack) to the eMMC.
8. **Verify on the panel** before considering it done: display comes up, Wi-Fi onboarding works, control panel reachable.

> **Note for the doc maintainer:** record the confirmed BIOS-entry key, the exact "auto power on" setting label, and the eMMC device path/size in this section as they're discovered at bench.

---

## 5. Architecture overview

```
┌───────────────────────── MeLE Quieter 3Q (the "player") ─────────────────────────┐
│                                                                                   │
│   Web control panel  ──►  Library (local storage)  ──►  Display (Chromium kiosk)  │
│        ▲                        ▲                              │                   │
│        │                        │                              ▼                   │
│   Browser on Mac/phone     Source layer                  26" square panel (HDMI)   │
│   (http://openobject.local) ├─ web upload (default)                                │
│                             ├─ pull from share (optional)                          │
│                             └─ on-chain NFT (future seam)                          │
└───────────────────────────────────────────────────────────────────────────────────┘
```

The display, control panel, and display-page are all **web-based and served by the player itself**. Files arrive through the **pluggable source layer**, land in the **local library**, and are rendered by **Chromium in kiosk mode**.

---

## 6. Display / render layer

**Render the display through Chromium in kiosk mode**, pointed at a local page that cycles the rotation. This is the deliberate architectural choice and it drives several requirements below.

**Why the browser engine:** the owner's real-world library is a polyglot of formats — AVIF (incl. animated), animated WebP, GIF, PNG transparency, plus MP4/MOV. A browser engine decodes all of these natively with one renderer, and `fit`/`fill` plus video looping fall out of standard CSS/HTML. A native image viewer + separate video player would require bolting on a separate decoder for half these formats and special-casing the animated ones.

**Supported formats (v1):**

| Category | Formats | Behavior |
|---|---|---|
| Stills | JPEG, PNG | Hold for set duration. PNG transparency renders against **black**. |
| Animated | GIF, WebP, AVIF | Animate and **loop to fill** their set duration. **Never freeze on frame one.** |
| Video | MP4, MOV | **Always loop.** "Full length" or fixed duration (see §7). No audio (§12). |

**Explicitly ignored (v1):** HEIC, SVG (deferred — renders unpredictably at arbitrary canvas sizes), PSD, CR2 (raw), GLB (3D model), and all OS/working-file noise (`.DS_Store`, `.docx`, `.xlsx`, etc.). The player simply skips unsupported files — **no conversion step on ingest** (uploads stay byte-for-byte).

**Display surface — edge-to-edge, no chrome.** The display page is a full-panel **black stage** (`100vw × 100vh`; zero margin, padding, border, scrollbars, or UI). Media renders to the **physical edges of the panel**; OpenObject adds **no decorative frame or border, ever**. In Fit mode the surrounding black is bare stage — not a frame.

**Fit vs Fill (per-clip; v1 default is _Fit_ / original aspect ratio):**

- **Fit** = `object-fit: contain` — entire image visible at its **original aspect ratio**; black fills the leftover. Nothing cropped. **This is the default.**
- **Fill** = `object-fit: cover; object-position: center` — image scaled to cover the full square, cropping the overflow **symmetrically from the center**: left/right trimmed for landscape, top/bottom for portrait. The center is always kept.

The square (1:1) panel makes this choice matter more than on a normal screen, because almost nothing displayed is square — hence per-clip control. **v1 uses center-crop only**; adjustable crop position (e.g. bias toward the top to preserve faces) is a documented future enhancement (§17).

---

## 7. Content model

**Library + Rotation + Pin.**

- **Library** — everything ever uploaded; stays on the player's local storage.
- **Rotation** — the subset currently cycling on the panel, in a chosen order. Order is **Sequence**, **Shuffle**, or **Random**:
    - **Sequence** — plays in the order you set, looping.
    - **Shuffle** — a randomized *pass*: every clip plays once before any repeats, then reshuffles. Good coverage, no near-term repeats.
    - **Random** — an independent random pick each advance; may repeat a clip, no coverage guarantee.
- **Pin (a.k.a. "permanent"/"hold")** — optionally elevate **one** clip to display permanently, overriding the cycle until unpinned. Supports the workflow "upload several, then manually promote whichever one to permanent," and the degenerate case "I just want one image up forever."

Uploading **adds to the library**. A "daily refresh" habit is achieved by curating which library items are in the rotation (clearing/selecting), so both mental models — daily-replace and growing-curated-library — are served by the same structure. _(**Confirmed 2026-06-11:** library+select, not hard replace-on-upload.)_

**Duration:**

- A **global default duration** applies to every clip unless overridden. Each clip may **override** with its own duration. (Drop 10 clips → they inherit the default → tweak the few exceptions.)
- **Images** need an explicit duration (how long to hold the still).
- **Video** duration is either **"full length"** (play once through, then advance) or a **fixed duration** (loop to fill that time — a 6s clip set to 30s loops five times). **All video always loops; none ever plays once and freezes on a last frame.**
- **Animated formats (GIF/WebP/AVIF)** follow the same loop-to-fill rule as video.

---

## 8. Source layer (pluggable)

Design the source layer as a **clean interface**: *a source provides files to the library.* The uploader is not hard-wired as the only way files can arrive. This is good architecture regardless, and it is what lets future sources (§17) slot in without a teardown.

**v1 sources:**

- **Web upload (default).** Open the control panel in a browser → drag art onto the page, or tap to choose files → it lands in the library. Works identically from Mac, iPhone, iPad, Windows. **No mounting, no credentials.** This is the everyday path.
- **Pull from a network share (optional).** For power users who'd rather point at an existing folder on their machine. Player connects to an SMB share (Samba speaks both macOS and Windows file sharing) and syncs from it. Requires address + credentials in the control panel.

**Not a source / explicitly out of scope:** Git/GitHub is **not** part of the content path in any form. GitHub is used solely for **source-code management and distribution** of OpenObject itself (§15). Art never touches the repo.

---

## 9. Storage & sync model

**Progressive sync, full local mirror at rest, buffered fallback only when forced.**

- **Progressive sync (first run):** grab the first few clips, **start the rotation as soon as the first clip lands**, then continue pulling the rest into local storage in the background while the panel is already showing art. The display waits only for the first clip, not the whole library. The rotation must **fold in newly-arrived clips gracefully without restarting or stuttering** the loop.
- **Full local mirror (steady state):** once synced, the entire library lives on the eMMC and **playback is always local** — a 30 MB clip loads from local storage in a fraction of a second. The network is used **only when the library changes** (add/remove). No clip is ever downloaded or deleted at display time. There is **no per-clip download→display→purge loop** — that design is explicitly rejected because it puts Wi-Fi in the playback path and churns the eMMC.
- **Capacity:** the target library (hundreds of ~30 MB clips ≈ 3–30 GB) fits comfortably in ~100+ GB of free eMMC after a slim Linux install. microSD expands it further.
- **Buffered mode (optional fallback):** engages **only** when a library genuinely exceeds free storage (e.g. a future owner with a 300 GB 4K archive). It is **not** strict per-clip purge; it is a **prefetch buffer with least-recently-shown eviction** — keep the next N clips staged ahead of playback, evict oldest-shown only under space pressure, so the network is never what playback waits on. Matt's default never engages this; it exists for the next-owner kit.

A single **storage-mode setting** governs this: default **"full sync"**, with **"buffered"** offered only when the library outgrows the disk.

---

## 10. Power handling

The physical power button is hard to reach when wall-mounted. This is fully solved in software/BIOS:

- **Auto Power On (BIOS):** enabled during reflash (§4). The unit boots the moment it receives power. Power control becomes the wall outlet (or an optional smart plug). Also means the frame **self-recovers after a power blip** instead of waiting for a button press.
- **Soft restart / shutdown (web UI):** the control panel exposes **Restart** and **Shut down**, initiated from the owner's browser. Handles all intentional reboots without reaching behind the panel.
- **Hard lockup (rare):** power-cycle the outlet; an optional ~$15 smart plug makes this a phone tap. Not required.

---

## 11. Network & first-run onboarding

A fresh, wall-mounted box has no art and isn't on Wi-Fi yet — but the control panel is reached *over* Wi-Fi. Solve the chicken-and-egg with a **self-broadcast setup network** (the standard headless-device pattern; keyboard-free and next-owner-friendly):

1. On first boot with no known network, the player **broadcasts its own temporary Wi-Fi network** (e.g. `OpenObject-Setup`).
2. The owner joins it from a phone/laptop; a **captive setup page** appears.
3. They pick their home network and enter the password.
4. The player **switches over** to the home network and the setup AP shuts down.
5. This **self-heals** if home Wi-Fi credentials later change (box falls back to setup AP).

**Reaching the control panel:** `http://openobject.local` (mDNS), works natively on Mac/iPhone. The setup page also **displays the raw IP** as a fallback (e.g. for Windows clients without mDNS).

**Wired option:** the free Gigabit Ethernet port is a fully supported bonus, but **Wi-Fi is the baseline** — the kit must not require running a CAT5 cable, since the next owner may not be able to.

---

## 12. Settings & defaults

| Setting | v1 default | Notes |
|---|---|---|
| Audio | **Muted, always** | Silent art on a wall. Future: optional global "allow audio" toggle. |
| Control-panel access | **Open on LAN**, optional password | No login friction by default; password available for those who want it. |
| Idle / empty screen | **Branded card**, not black | Shows OpenObject mark + "add art at openobject.local". Takes a **logo asset** (Matt-supplied) so the mark drops in without redesign. |
| Display name / mDNS | `openobject.local` | IP fallback shown on setup page. |
| Fit/Fill default | **Fit** (original aspect ratio); settable | Applies to new clips; per-clip override always available. |
| Default duration | Settable global | Per-clip override always available. |

---

## 13. Sleep hours (v1 feature)

An **optional schedule to blank or dim the panel overnight** (configurable start/end). The panel otherwise runs 24/7; this is a longevity and preference feature (the owner dislikes it running at night). Build in v1. When asleep, the panel is blanked/dimmed; it resumes the rotation on schedule. Pairs cleanly with the display layer (no playback during the sleep window).

---

## 14. Branding asset

Matt is producing an **OpenObject mark** and will store it in the project (`/Users/mattlhx/Code/OpenObject`). Design the **fresh-boot screen** and **idle/empty screen** to consume a logo asset (with a tasteful text fallback if absent), so the mark drops in without layout changes. Aesthetic direction: understated, functional, no clutter.

---

## 15. Repository & distribution

- **Local root:** `/Users/mattlhx/Code/OpenObject` (already created).
- **GitHub:** Claude Code initializes the repo, structure, and first commit. The repo is **private during development** (2026-06-11) and intended to go **public** later to serve the next-owner mission. Claude drives all git operations; Matt approves pushes at checkpoints (this replaced the original "walk Matt through it step-by-step" plan — see §20).
- **Releases:** publish the **prebuilt USB installer image as a release asset** so a non-technical owner downloads one file instead of building anything. (Release assets hold large binaries; the repo proper does not.)
- Suggested repo layout:

```
OpenObject/
├─ README.md                ← public next-owner narrative + quickstart (generated during build)
├─ docs/
│  ├─ HANDOFF.md            ← this build spec (working doc; kept current)
│  ├─ SETUP-GUIDE.md        ← casual-user guide (§16; kept current in tandem)
│  └─ appendix-whitewalls-reset.md  ← original Android reset procedure (§18)
├─ player/                  ← OpenObject stack (web server, control panel, display page, sync, etc.)
├─ installer/              ← bootable USB build
├─ assets/                  ← OpenObject mark, idle/boot screens
└─ ...
```

---

## 16. Documentation requirement (two audiences, kept in lockstep)

Maintain **two** living documents as the build proceeds — not one written once and left to drift:

1. **`docs/HANDOFF.md` (this doc)** — the engineering working doc. Accumulates design tweaks, troubleshooting notes, bench discoveries, and test results.
2. **`docs/SETUP-GUIDE.md`** — the **casual-user** guide. No engineering. For someone who has never seen the handoff and never will.

**Discipline:** whenever a change affects what a new user does — a different BIOS key, an added step, a renamed setting — **update the Setup Guide in the same change.** The Setup Guide must always reflect shipped behavior.

### Setup Guide scaffold (fill placeholders as values are confirmed)

> **What you need before you start**
> - A functioning **Infinite Objects XXL** unit (the 26" square frame) with its **MeLE Quieter 3Q** mini PC on the back.
> - **USB hub:** _[exact make/model — TBD, confirm after Matt's hardware arrives and is verified in the unit's clearance]_
> - **Right-angle USB-A extension:** _[exact make/model — TBD; CableCreation 2-pack (L+R) was ordered; record the one that fit]_
> - **USB keyboard:** _[exact make/model — TBD; Logitech K400 Plus was the plan]_
> - **USB flash drive:** ≥16 GB (for the installer).
> - **External USB drive:** ≥128 GB (only if preserving the original White Walls backup).
>
> **Steps** (kept in sync with the real procedure)
> 1. Plug the extension into the mini PC's free USB port; attach the hub; attach keyboard + installer drive.
> 2. Power on and enter the BIOS _(key: TBD)_; set USB boot; enable Auto Power On.
> 3. Boot the installer. (Optional: back up the original software first.)
> 4. Install OpenObject; wait for the panel to show the OpenObject screen.
> 5. Join the temporary **OpenObject-Setup** Wi-Fi from your phone; pick your home Wi-Fi; enter the password.
> 6. Open **http://openobject.local** in any browser; drag your art onto the page; set durations and fit/fill; done.

---

## 17. Future enhancements (documented seams, not built in v1)

- **On-chain / NFT source.** The marquee future feature. Reading on-chain art is a **resolution problem, not a display problem**: an NFT is a pointer (contract address + token ID) whose `tokenURI` → metadata → media URL resolves to a file — and that file is a **JPEG/PNG/GIF/MP4/AVIF the v1 display engine already handles**. Intended approach: a **resolver/connector API** (e.g. Alchemy, QuickNode, Reservoir, OpenSea) so the player does *not* run nodes, RPC endpoints, or IPFS gateways itself — connect once, the service returns a media URL, the player downloads it. This slots in as a **third source type** alongside web upload and pull-from-share; everything downstream (sync, library, rotation, pin, fit/fill, loop) is unchanged. **v1 action:** keep the source layer a clean interface so this is a plug-in later, not a teardown. Build none of it now.
- **Adjustable crop position** for Fill (e.g. keep the top of portraits). v1 is center-crop only.
- **SVG support.** Trivial to add under the browser-render approach if wanted later; deferred because it renders unpredictably at arbitrary sizes.
- **Global "allow audio" toggle.** v1 is muted-always.
- **Smart-plug integration** for hard-lockout recovery.

---

## 18. Appendix — original White Walls reset (for owners who want to keep it)

Preserved from the vendor's tutorial so a future owner can re-register the **original** Android software *while the vendor's servers still exist*. Not part of OpenObject; offered as a courtesy in the repo.

The original software is a standard Android app on Android-x86. To manually reset its account registration:

1. Connect a USB-A mouse to the mini PC.
2. Reveal the system menu: click-and-drag **downward from the very top** of the screen (this is the Android notification shade; "begin click at top and drag down" — it's fiddly).
3. Expand the menu; click the **Settings** cog.
4. **Apps & Notifications** → the **White Walls** app → **Storage & Cache** → **Clear Storage** → **OK** to delete app data.
5. Click the circular **home** button to exit; the unit can re-register as a new White Walls device.

> The full pre-wipe **eMMC image** (§4, step 6) is the more complete preservation: it captures the entire original install, not just a registration reset.

---

## 19. Open items for Matt to confirm/supply

- [ ] **Hardware models** (hub, right-angle extension, keyboard) — confirm after delivery + fit-test; fill into §16.
- [x] **Logo / OpenObject mark** — supplied by Matt; optimized marks in `assets/branding/` (source masters in `Logo/`, gitignored). Transparent / white-on-dark variants derived in Phase 1.
- [ ] **Bench-verified specs** — exact eMMC free space, Wi-Fi module/driver status, BIOS-entry key, Auto-Power-On label.
- [x] **GitHub repo** — created **private** (2026-06-11); goes public later.
- [x] **Content model confirmed** (2026-06-11) — library+select, not replace-on-upload.

---

## 20. Build decision log

Living record of decisions taken during the build (newest first). When any of these affect user-facing behavior, the Setup Guide is updated in the same change (§16).

### 2026-06-12 — Bench caution: screws above the MeLE
- **Do not remove the two screws on the bracket above the MeLE** when working at the
  back of the XXL — they retain captive nuts inside the chassis that fall in if the
  screws are backed out, forcing a near-full teardown to recover. Documented in §4 and
  the Setup Guide. (Bench lesson from Matt.)

### 2026-06-11 — Branding asset approach
- **Idle/boot-screen logo variants will be produced with Potrace → SVG**
  (`openobject-logo.svg`): single-color and transparent so CSS recolors it
  white-on-dark or black-on-light; transparent PNG exports derived from it as needed.
  Trace source: the **2k master** (`Logo/logo-2k.png`), falling back to `logo_orig.png`
  if the higher-res export proves a soft upscale rather than added detail — the 2k/4k
  files are near-uncompressed, so verify edge crispness at trace time. The committed
  PNG marks (≤1024) stay sourced from the clean `logo_orig.png`.
  A plain raster color-inverse was rejected (trivial — Matt does that in Photoshop if
  ever needed). **SVG here is a UI/brand asset only**; displayed user *art* in SVG
  stays deferred per §6. (§14)
- **Logo source re-centered** by Matt (subtle but critical glyph centering fix); the
  committed marks were refreshed from the new source (commit `df57ec6`).

### 2026-06-11 — Phase 0 kickoff
- **Content model confirmed:** Library + select — persistent library, curated rotation, pin one clip. Not replace-on-upload. (§7)
- **Stack chosen:** Node.js + Express + vanilla HTML/CSS/JS + SQLite, no build step — one language across server and the browser display page, chosen for revivability. (§5)
- **Display is edge-to-edge with zero chrome:** full-panel black stage, no decorative frame/border/padding, media to the physical edges. (§6)
- **Default render mode is Fit** (original aspect ratio); per-clip Fill override retained. An earlier "Fill by default" idea was rejected. (§6, §12)
- **Rotation order gains Random** alongside Sequence and Shuffle — three modes, defined in §7.
- **Repo is private for now,** intended to go public later; the next-owner mission still drives design. (§15)
- **Logo supplied** by Matt; optimized marks committed under `assets/branding/`, large masters kept out of git. (§14, §19)
- **Workflow:** Claude drives all git/gh; commits + pushes happen at checkpoints on Matt's approval; outward-facing actions gated. No hardware access yet — Linux/kiosk/installer is Phase 2.

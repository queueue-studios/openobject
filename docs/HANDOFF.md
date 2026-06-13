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

The mini PC is a **MeLE Quieter 3Q** (confirmed from the unit's label; the BIOS reports board name **`XXL`** — an Infinite Objects custom badge on the same N5105 platform).

| Attribute | Value |
|---|---|
| Model | MeLE Quieter 3Q (BIOS board name `XXL`) |
| CPU | Intel Celeron **N5105** (Jasper Lake / "JasperLake ULX"), 2.00 GHz, **x86-64** — _bench-confirmed 2026-06-13; earlier "N5100" was wrong_ |
| RAM | 8 GB LPDDR4x _(typical config; not yet confirmed at bench)_ |
| Storage | **~256 GB eMMC** _(Android reported ~252 GB usable / ~93 GB free; UEFI device id `A3V012`; confirm exact size/path from Linux at install — earlier "128 GB" was wrong)_ |
| Expansion | microSD slot (pressure valve for larger libraries) |
| Networking | Onboard **Wi-Fi 5** + **Gigabit Ethernet** (RJ45) |
| Power | 12 V / 2 A barrel jack |
| FCC TX ID | PD99560D2 _(use to confirm Wi-Fi module / Linux driver at bench)_ |
| Serial | 8ICH4F310P530467 |
| MAC | 00CE39D53121 |

**Ports on the outward-facing edge:** 1× USB-A 3.0, 3.5 mm audio, microSD, 2× HDMI, 1× USB-C (DP-capable), 1× Gigabit Ethernet, barrel power.

**Critical hardware facts for the build:**

- This is a **normal x86 PC with a UEFI BIOS**, not an Android appliance. Infinite Objects installed **Ubuntu Linux** and runs the original "White Walls" player as an **Android app inside Waydroid** — a **LineageOS Android 11** container (`lineage_waydroid_x86_64`, build `RQ3A.211001.001`) on the Linux host — which is *why the original UI looks like Android*. Underneath it boots like any PC and runs Linux from a USB stick. **Confirmed at bench (2026-06-13):** UEFI firmware (AMI Aptio `ML_JPL1 V1.0.0 x64`, core 2.22.1282), **`Del`** enters Setup, **no BIOS password**, **Secure Boot off**, boot mode **UEFI**; the factory boot entry is `ubuntu (eMMC A3V012)`.
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

> **Bench note (2026-06-13):** the factory unit already runs **Ubuntu** on this exact hardware (N5105 iGPU, the square HDMI panel, onboard Wi-Fi, the USB hub), so a Debian-based install is low-risk — graphics, panel, and networking are all known-good under mainstream Linux. The factory stack is heavier than ours (Ubuntu → Waydroid container → Android → White Walls) and boots slowly (~1 min to art); our native Node + Chromium-kiosk path should boot markedly faster.

---

## 4. Access & reflash procedure (one-time bench/in-place session)

This is the procedure to convert a stock XXL to OpenObject. It is performed once. The unit can stay wall-mounted; the outward-facing port edge remains reachable.

> **⚠️ Caution — do NOT remove the two screws above the MeLE.** On the back of the XXL, the two screws on the bracket/plate directly **above** the MeLE mini PC retain captive nuts on the *inside* of the chassis. Loosening or removing them drops those nuts inside the unit, and recovering them requires a **near-full disassembly and reassembly** of the XXL. They are **not** part of this procedure — leave them alone.

**Access hardware** (the owner-supplied kit — exact models recorded in the Setup Guide, §16):
- **Left-angle** USB-A extension from the single free port out to a reachable spot, then a USB hub on the end (one port can't host both the installer stick and a keyboard). The **left** angle is deliberate: it routes the cable clear of the frame controller's **power socket**, which sits immediately beside that USB port and must stay reachable to seat the power cord. (Confirmed part: CableCreation **CC0516** — see §16.)
- USB keyboard (a keyboard+touchpad combo on one dongle is ideal).
- USB flash drive (≥16 GB) for the Linux/OpenObject installer.
- External USB drive (≥128 GB; small USB SSD ideal) for the pre-wipe backup image.

**Procedure:**

1. **Connect** the hub to the free USB-A port; attach keyboard + installer flash drive.
2. **Enter the BIOS** at power-on by tapping **`Del`** _(confirmed 2026-06-13)_. The IO splash uses **Quiet Boot**, so no "press a key" prompt appears — tap `Del` repeatedly from the instant you power on, during the black screen (that's POST). The panel then shows the BIOS screen over HDMI. _(On a Logitech K400, `Del` is a direct key; the F-keys are Fn-shifted.)_
3. **Set boot order / boot menu** to boot from the USB flash drive. _(With the stick inserted it appears as a new boot option; use a one-time boot menu — likely `F7` — or **Save & Exit → Boot Override**, or set Boot Option #1. Confirm the boot-menu key with the stick in hand.)_
4. **Auto power-on — nothing to set.** _(Confirmed 2026-06-13:)_ this BIOS exposes **no** "Auto Power On / Restore AC Power Loss / State After G3" toggle (checked `Chipset → PCH-IO Configuration`), and the unit already boots on its own when power is applied — auto-on is the firmware default. So it boots whenever it receives power, no button press, nothing to enable (see §10). _(If a future unit doesn't auto-boot, the only place an ODM might hide it is `Advanced → Customer Exclusive Functions`.)_
5. **Boot the live USB.**
6. **BACK UP FIRST — image the existing eMMC** to the external drive (full-disk image). This preserves the original **Ubuntu + Waydroid (White Walls)** install in case the owner ever wants it back *while the vendor's servers still exist*. This is the clean, ADB-free way to capture it. **Do this before any wipe.**
7. **Install OpenObject** (Linux + the OpenObject stack) to the eMMC.
8. **Verify on the panel** before considering it done: display comes up, Wi-Fi onboarding works, control panel reachable.

> **Recorded at bench (2026-06-13):** BIOS-entry key = **`Del`**; there is **no** "auto power on" setting (auto-on is the firmware default — see step 4); eMMC ≈ **256 GB**, UEFI id `A3V012` (confirm the Linux device path, e.g. `/dev/mmcblk*`, when installing).

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

**Why the browser engine:** the owner's real-world library is a polyglot of formats — AVIF (incl. animated), animated WebP, GIF, PNG transparency, plus MP4/MOV/WebM. A browser engine decodes all of these natively with one renderer, and `fit`/`fill` plus video looping fall out of standard CSS/HTML. A native image viewer + separate video player would require bolting on a separate decoder for half these formats and special-casing the animated ones.

**Supported formats (v1):**

| Category | Formats | Behavior |
|---|---|---|
| Stills | JPEG, PNG | Hold for set duration. PNG transparency renders against **black**. |
| Animated | GIF, AVIF, WebP | Animate and **loop to fill** their set duration. **Never freeze on frame one.** |
| Video | MP4, MOV, WebM | **Always loop.** "Full length" or fixed duration (see §7). No audio (§12). |

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
- **Rotation** — the subset currently cycling on the panel, in a chosen order. Order is **Sequence** or **Shuffle**:
    - **Sequence** — plays in the order you set, looping.
    - **Shuffle** — a randomized *pass*: every clip plays once before any repeats, then reshuffles. Good coverage, no near-term repeats.
- **Pin (a.k.a. "permanent"/"hold")** — optionally elevate **one** clip to display permanently, overriding the cycle until unpinned. Supports the workflow "upload several, then manually promote whichever one to permanent," and the degenerate case "I just want one image up forever."

Uploading **adds to the library**. A "daily refresh" habit is achieved by curating which library items are in the rotation (clearing/selecting), so both mental models — daily-replace and growing-curated-library — are served by the same structure. _(**Confirmed 2026-06-11:** library+select, not hard replace-on-upload. **Built 2026-06-13:** per-item add/remove toggle in the Library tab; Sequence order user-arranged by drag or ↑/↓ in the Rotation tab; §20.)_

**Duration — one global, equal time for every piece (confirmed 2026-06-12).**

- A **single global duration** applies to **every** piece in the rotation — equal time per content piece. There is **no per-clip duration**.
- **Stills** (JPEG/PNG) hold for the duration.
- **Animated** (GIF/WebP/AVIF) and **video** (MP4/MOV/WebM) **loop to fill** the duration: a piece shorter than it repeats; a piece **longer** than it is cut off when the timer advances. **Video always loops; it never freezes on a last frame.**

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
    - **Confirmed (Matt, 2026-06-13):** this unit **boots when the power cord is unplugged and replugged**, so cycling the outlet reliably boots it and the hard-to-reach physical power button is a **non-issue**. After a **Shut down**, you power the frame back on by replugging (or toggling a smart plug). **Resolved at bench:** there is **no Auto-Power-On toggle** in this BIOS (checked `Chipset → PCH-IO Configuration` — no "State After G3" / "Restore AC Power Loss"); auto-on is the **firmware default**, which is exactly this replug-boot behavior. Nothing to set.
- **Soft restart / shutdown (web UI):** the control panel exposes **Restart** and **Shut down**, initiated from the owner's browser. Handles all intentional reboots without reaching behind the panel.
- **Hard lockup (rare):** power-cycle the outlet; an optional ~$15 smart plug makes this a phone tap. Not required.

**Built 2026-06-13 (§20).** The control panel's **Settings → Power** card ships **Restart** and
**Shut down**. **Restart is real now**: an app-level soft-restart via the supervisor (exit →
relaunch, the same path as self-update, §15), so it works browser-only with no hardware and behaves
identically once systemd runs it on the device. **Shut down** is a visible-but-inert **stub** in
Phase 1 — the dev Mac has nothing to power off and must not be powered off; Phase 2 wires it to a
real OS power-off (e.g. `systemctl poweroff`). Phase 2 can also add a **full device reboot**
(`systemctl reboot`) alongside the app-restart — the bigger hammer for OS-level issues. Per the
Auto-Power-On point above, a real power-off returns when power is restored, so a true "stays off"
is the outlet / smart plug.

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

**Built 2026-06-13 (§20, Phase-1 stub).** The control panel's **Settings → Wi-Fi** card explains the
first-run onboarding flow above; the setup AP + captive page themselves are **Phase 2** (they need the
device's networking). The card also shows **how to reach the control panel now** — the live LAN
address(es) (`http://<ip>:<port>`, from `GET /api/system`) plus the `openobject.local` name that
resolves on the installed frame — which is real and useful in Phase 1.

**Reference — observed Infinite Objects onboarding (2026-06-13), and our refinements.** Matt captured
the stock XXL's Wi-Fi setup; it's a proven flow worth building on. Observed: the frame's screen shows
**two QR codes** — (1) a Wi-Fi-join QR for its setup AP (`IOXXL-<id>`, WPA password `infinite`), and
(2) a URL QR to a config page at `ioxxl.local`. On the page you enter **SSID + Pass Phrase → Connect**;
the phone then shows "configuration in progress — wait for confirmation on the screen," and the frame
confirms "Successfully Connected… searching for updates and rebooting."

Refinements to adopt for OpenObject (Phase 2 — build with the hardware):
- **QR codes on the frame's setup screen** — the biggest win. The branded boot/idle screen, in its "no
  network yet" state, *becomes* the setup screen: mark + a **join-AP QR** (one-tap join, no typing) + an
  **open-config QR** (one tap to the captive page) + a manual fallback (network name, password, URL).
- **Plain labels** on the config page — "Wi-Fi network name" and "Password", not "SSID" / "Pass Phrase".
- **Pick the network from a scanned list** rather than typing the SSID (typo-proof; manual entry as a
  fallback for hidden networks).
- **Two-screen confirmation** — when the frame leaves its own AP to join home Wi-Fi, the phone loses
  contact with it, so success is confirmed on the **frame's screen** ("Connected ✓") while the phone
  shows "applying — watch the frame."
- **Recovery line + self-heal** — on failure the setup AP returns; tell the user to re-join it and retry.
- **AP naming/password** — `OpenObject-<id>` (a short unique suffix so two frames don't collide); open
  network vs. a QR-encoded password is a Phase-2 call (the join-QR makes a password basically free).

The stock screens themselves are reference only — captured here as learnings, not committed (art and
photos never enter the repo, §8). Build none of this in Phase 1.

---

## 12. Settings & defaults

| Setting | v1 default | Notes |
|---|---|---|
| Audio | **Muted, always** | Silent art on a wall. Future: optional global "allow audio" toggle. |
| Control-panel access | **Open on LAN**, optional password | No login friction by default; password available for those who want it. |
| Idle / empty screen | **Branded card**, not black | Shows OpenObject mark + "add art at openobject.local". Takes a **logo asset** (Matt-supplied) so the mark drops in without redesign. |
| Display name / mDNS | `openobject.local` | IP fallback shown on setup page. |
| Fit/Fill default | **Fit** (original aspect ratio); settable | Applies to new clips; per-clip override always available. |
| Display duration | **Settable global** (seconds / minutes / hours) | One equal-time duration for **every** piece; no per-clip override. |
| Rotation order | **Sequence** | Sequence / Shuffle (§7); settable. |
| Sleep hours | **Off** (no windows enabled) | Up to two daily blank windows (12h clock) + manual "Blank panel"; dimmed-logo sleep screen (§13). |
| Updates | **Manual check; track `main`** | Self-update from GitHub via the control panel (§15). Owner-initiated; fast-forward only. |

---

## 13. Sleep hours (v1 feature)

An **optional schedule to blank or dim the panel overnight** (configurable start/end). The panel otherwise runs 24/7; this is a longevity and preference feature (the owner dislikes it running at night). Build in v1. When asleep, the panel is blanked/dimmed; it resumes the rotation on schedule. Pairs cleanly with the display layer (no playback during the sleep window).

**Built 2026-06-13.** Up to **two daily windows**, each with its own **enable checkbox** —
covering both "I'm at work" and "I'm asleep." Times are entered on a **12-hour clock with an
AM/PM toggle** and may cross midnight (an auto **"overnight"** tag flags a window that wraps).
A manual **"Blank panel"** toggle in the control-panel header turns the art off on demand,
independent of the schedule — the companion to scheduled sleep, and the answer to "how do I
stop the display right now?". While asleep, **playback stops** and the panel shows the **sleep
screen**: the same boot/idle mark at the **same size and placement, dimmed (~0.2 opacity) and
with no caption** underneath. To rest the panel it does a slow, imperceptible **pixel-shift**
every ~90 s (the standard anti-burn-in technique — chosen over a periodic fade as sufficient on
its own; on this LCD it's belt-and-suspenders anyway). The server computes `asleep` (schedule
or manual) and the display renders on that one signal, flipping within ~5 s of a boundary.
Phase 1 blanks in **software**; dimming the actual **backlight** is a Phase 2 hardware hook.

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

### In-place updates (self-update from GitHub) — Phase 1

The player updates itself from this GitHub repo, **from the control panel** — no
reflash, no SSH, no rebuild. This is GitHub's only runtime role; **art still never
touches the repo** (§8). The player runs as a **git checkout of the repo**, so "update"
is a `git` fast-forward plus a restart.

**Owner flow:** the control panel shows the running version and a **Check for updates**
button → a `git fetch` compares the local checkout to its upstream tracking ref → if
newer, it shows what's available → **Update & restart** fast-forwards the checkout
(`git pull --ff-only`), reinstalls dependencies if they changed, and relaunches the
player. The idle/boot screen flashes briefly; the panel returns on the new version, and
`/healthz` reports the version that came back up.

**Guardrails:**
- **Fast-forward only** — never a force-reset. If the checkout has diverged (local
  edits) the update refuses and says so rather than clobbering it.
- **Runtime data is never touched.** `player/data/` and uploads are gitignored, so a
  pull never disturbs the library, settings, or art.
- **Update channel** (setting): track the **`main`** branch (default) or **tagged
  releases only** (conservative). Releases also carry the prebuilt USB image (above),
  but self-update pulls *source*, not the image.
- **Local-first and offline-safe** (§9): if GitHub is unreachable the check fails
  gracefully and playback is unaffected. Updating is always **owner-initiated** — never
  automatic, never in the playback path.

**Phase split:** Phase 1 builds and tests the whole mechanism on macOS — check,
fast-forward, dependency reinstall, version reporting via `/healthz`, and a dev-friendly
restart (the supervisor relaunches `node server.js`). It lands **after the core control
panel**, since the UI lives there. Phase 2 only swaps the restart for the OS service
manager (a systemd unit restarts the player on the device); the mechanism above is
unchanged.

**Built 2026-06-13.** Lives in the control panel's **Settings** tab. `npm start` runs a tiny
**supervisor** (`player/supervisor.js`) that relaunches `node server.js` when the player exits
with restart code 75 after an update; `npm run start:direct` runs the server without it (manual
restart). Routes: `GET /api/update` (no-network status for page load), `POST /api/update/check`
(fetch + compare to the channel's target), `POST /api/update/apply` (fast-forward + deps-if-changed
+ restart), `PUT /api/update/channel`. `/healthz` returns `{version, commit}` so the panel can
confirm the relaunched version. All git runs via `execFile` against the **repo root**; the player
app and its `package.json`/lockfile live in `player/`, so a dependency reinstall runs there. The
card shows `version · build date · commit` (no jargon); the update channel is a backend setting
(`update_channel`: `main` | `releases`) but v1 surfaces no toggle and tracks `main` (§20). Verified on macOS against a
throwaway bare-clone "fake origin" (no real upstream commits, never touches GitHub): check →
fast-forward + restart (commit flips on `/healthz`) → divergence refusal, plus the offline and
not-a-git-checkout paths. Phase 2 swaps the supervisor for a systemd unit; the mechanism is
unchanged.

---

## 16. Documentation requirement (two audiences, kept in lockstep)

Maintain **two** living documents as the build proceeds — not one written once and left to drift:

1. **`docs/HANDOFF.md` (this doc)** — the engineering working doc. Accumulates design tweaks, troubleshooting notes, bench discoveries, and test results.
2. **`docs/SETUP-GUIDE.md`** — the **casual-user** guide. No engineering. For someone who has never seen the handoff and never will.

**Discipline:** whenever a change affects what a new user does — a different BIOS key, an added step, a renamed setting — **update the Setup Guide in the same change.** The Setup Guide must always reflect shipped behavior.

### Setup Guide scaffold (fill placeholders as values are confirmed)

> **What you need before you start**
> - A functioning **Infinite Objects XXL** unit (the 26" square frame) with its **MeLE Quieter 3Q** mini PC on the back.
> - **USB hub:** UGreen USB 3.0 Hub, 4-port, 2 ft (model **25946**).
> - **Left-angle USB-A extension:** CableCreation USB 3.0 Extension, Left Angle, 1 ft (part **CC0516**). _(The **left** angle is the one that fit — it clears the controller's power socket beside the USB port.)_
> - **USB keyboard:** Logitech **K400 Plus** (keyboard + touchpad on one receiver).
> - **USB flash drive:** ≥16 GB (for the installer).
> - **External USB drive:** ≥128 GB (only if preserving the original White Walls backup).
>
> **Steps** (kept in sync with the real procedure)
> 1. Plug the extension into the mini PC's free USB port; attach the hub; attach keyboard + installer drive.
> 2. Power on and enter the BIOS by tapping **`Del`** (the splash hides the prompt — tap from the black screen); set USB boot. _(No "Auto Power On" to enable — the frame already powers on by itself when it has power.)_
> 3. Boot the installer. (Optional: back up the original software first.)
> 4. Install OpenObject; wait for the panel to show the OpenObject screen.
> 5. Join the temporary **OpenObject-Setup** Wi-Fi from your phone; pick your home Wi-Fi; enter the password.
> 6. Open **http://openobject.local** in any browser; drag your art onto the page; set durations and fit/fill; done.

---

## 17. Future enhancements (documented seams, not built in v1)

- **On-chain / NFT source.** The marquee future feature. Reading on-chain art is a **resolution problem, not a display problem**: an NFT is a pointer (contract address + token ID) whose `tokenURI` → metadata → media URL resolves to a file — and that file is a **JPEG/PNG/GIF/MP4/AVIF the v1 display engine already handles**. Intended approach: a **resolver/connector API** (e.g. Alchemy, QuickNode, Reservoir, OpenSea) so the player does *not* run nodes, RPC endpoints, or IPFS gateways itself — connect once, the service returns a media URL, the player downloads it. This slots in as a **third source type** alongside web upload and pull-from-share; everything downstream (sync, library, rotation, pin, fit/fill, loop) is unchanged. **v1 action:** keep the source layer a clean interface so this is a plug-in later, not a teardown. Build none of it now.
- **Web / HTML art pieces (interactive & generative).** *(Working name: "HTML" content — to be
  renamed as we learn the space.)* Some art is not a still or a clip but a **live web page** —
  a generative/interactive `index.html` (often Arweave/IPFS-hosted) that renders on a canvas
  and may expose its own controls. **First target use case:** Bryan Brinkman's *"Azulejo Galo"*
  (an Arweave `index.html` carrying query params for token/wallet/etc.), where clicking the
  piece reveals a **"Toggle Rotation"** control that animates it. Intended UX: the owner
  **pastes a URL**, optionally assigns a **name** and **special functions** (e.g. auto-engage
  "Toggle Rotation"); from then on the piece is a normal library card — Rotation, Pin, duration,
  Fit/Fill behave as usual.
    - **Approach: a curated by-name handler registry, not a generic web automator.** We can't
      drive the infinite ways web content is built and won't try. A small **registry of handlers
      for known/featured collections** maps a recognized collection (or URL pattern) → its
      display name + artist + any **bespoke functions** (hide the page's own UI, programmatically
      engage a control, set a motion query-param, …). Unknown URLs embed as a plain page; only
      recognized collections get white-glove handling — onboarded by **adding a handler, not
      changing the engine**.
    - **Constraints to resolve when built:** a new render kind **`web`** (iframe / Chromium
      webview) alongside still/animated/video; **Fit/Fill is fuzzy** for a page with no intrinsic
      aspect ratio (likely "fill the stage," sized per-collection in the handler); **local-first
      tension (§9)** — a remote URL puts the network in the playback path, so it may need a
      snapshot/cache or be accepted as the one online-dependent kind; **driving the page's own
      controls is cross-origin-blocked** from our page, so automated control (the "Toggle
      Rotation" trigger) most likely rides on the **Chromium kiosk layer (Phase 2)** via script
      injection or known URL params, while the paste-URL/name/functions UX and the `web` library
      row could land in Phase 1; and **trust/security** — remote HTML runs untrusted code on the
      frame, so sandbox the embed and treat the curated registry as the trusted path.

  Slots into the **pluggable source layer (§8)** as another way a piece enters the library;
  everything downstream (Rotation, Pin, duration) is unchanged. Related to but **distinct from the
  on-chain/NFT source** above (that resolves a pointer to a *media file* the v1 engine already
  plays; this renders a *live page*). **v1 action: log it; build none of it now.**
- **Adjustable crop position** for Fill (e.g. keep the top of portraits). v1 is center-crop only.
- **SVG support.** Trivial to add under the browser-render approach if wanted later; deferred because it renders unpredictably at arbitrary sizes.
- **Global "allow audio" toggle.** v1 is muted-always.
- **Smart-plug integration** for hard-lockout recovery.

---

## 18. Appendix — original White Walls reset (for owners who want to keep it)

Preserved from the vendor's tutorial so a future owner can re-register the **original** Android software *while the vendor's servers still exist*. Not part of OpenObject; offered as a courtesy in the repo.

The original software is a standard Android app running in **Waydroid** (a LineageOS Android 11 container) on **Ubuntu Linux**. To manually reset its account registration (all within the Android container's UI):

1. Connect a USB-A mouse to the mini PC.
2. Reveal the system menu: click-and-drag **downward from the very top** of the screen (this is the Android notification shade; "begin click at top and drag down" — it's fiddly).
3. Expand the menu; click the **Settings** cog.
4. **Apps & Notifications** → the **White Walls** app → **Storage & Cache** → **Clear Storage** → **OK** to delete app data.
5. Click the circular **home** button to exit; the unit can re-register as a new White Walls device.

> The full pre-wipe **eMMC image** (§4, step 6) is the more complete preservation: it captures the entire original install, not just a registration reset.

---

## 19. Open items for Matt to confirm/supply

- [x] **Hardware models** (2026-06-13) — UGreen 4-port USB 3.0 hub (**25946**); CableCreation **left-angle** USB 3.0 extension (**CC0516**); Logitech **K400 Plus**. Filled into §16 / Setup Guide.
- [x] **Logo / OpenObject mark** — supplied by Matt; optimized marks in `assets/branding/` (source masters in `Logo/`, gitignored). Transparent / white-on-dark variants derived in Phase 1.
- [~] **Bench-verified specs** (2026-06-13) — **BIOS-entry key `Del`** ✓; **Auto-Power-On = none / firmware auto-on** ✓ (no toggle exists); **eMMC ≈ 256 GB** (id `A3V012`) ✓; **CPU N5105** ✓; **UEFI + Secure-Boot-off** ✓. **Still TBD:** Wi-Fi module/driver under Linux (FCC TX ID `PD99560D2`), RAM, exact eMMC free space + Linux path.
- [x] **GitHub repo** — created **private** (2026-06-11); goes public later.
- [x] **Content model confirmed** (2026-06-11) — library+select, not replace-on-upload.

---

## 20. Build decision log

Living record of decisions taken during the build (newest first). When any of these affect user-facing behavior, the Setup Guide is updated in the same change (§16).

### 2026-06-13 — Hardware bench identification (Phase 2 kickoff)
First hands-on session with the actual XXL unit (original OS reachable). Identity **confirmed**; several prior assumptions **corrected**:
- **CPU = Intel Celeron N5105** (Jasper Lake / "JasperLake ULX"), 2.00 GHz — **§2 corrected from the wrong "N5100."** BIOS board name is **`XXL`** (IO custom badge; same N5105 platform as the MeLE Quieter 3Q label).
- **Original OS is Ubuntu + Waydroid, not "Android-x86."** Host = **Ubuntu Linux**; "White Walls" runs as an **Android app inside Waydroid** (a **LineageOS Android 11** container, `lineage_waydroid_x86_64`, `RQ3A.211001.001`). The Android-looking UI is the container. **§2, §4, §18 corrected.** (§18's notification-shade / Settings→Apps reset steps still apply — that's the container's UI.)
- **Firmware:** AMI Aptio `ML_JPL1 V1.0.0 x64` (core 2.22.1282, 12/2023). **`Del`** enters Setup (Quiet Boot hides the prompt — tap from the black screen). **No BIOS password** (Administrator access). **Secure Boot off.** **UEFI.** Boot entry `ubuntu (eMMC A3V012)`. → the **UEFI USB installer** path is clear, no signing/Secure-Boot hurdle.
- **Storage = ~256 GB eMMC** (id `A3V012`) — **§2 corrected from "128 GB."**
- **Auto-Power-On: no BIOS toggle exists** (checked `PCH-IO Configuration`; no "State After G3" / "Restore AC Power Loss"). Auto-on is the firmware default — matches the confirmed replug-boot (§10). The §19 "Auto-Power-On label" item resolves to *there isn't one*. **§4, §10, §19 updated.**
- **Access kit / BOM confirmed:** UGreen 4-port USB 3.0 hub (**25946**); CableCreation **left-angle** USB 3.0 extension (**CC0516**) — the **left** angle clears the controller's power socket beside the USB port; Logitech **K400 Plus**. Insert trick: slide the MeLE up to free the HDMI/USB-C, seat the extender, reseat, slide back down. **§4, §16, §19 + Setup Guide updated** ("right-angle" → "left-angle").
- **Reference:** factory stack boots slowly (~1 min to art) → our native Node + Chromium-kiosk should beat it easily; Ubuntu already drives the N5105 iGPU + square panel + Wi-Fi, so **Debian** is low-risk (§3).
- **Still TBD:** Wi-Fi module/driver under Linux (FCC TX ID `PD99560D2`), RAM, exact eMMC Linux path/free space — all gettable once our OS boots.

### 2026-06-13 — Shut down / Restart countdown-cancel; power-cycle boots confirmed
- **Power actions now arm a countdown the owner can cancel** (Matt): **Shut down** counts down
  **10s**, **Restart** **5s**, shown inline in the Power card with a **Cancel** button (replacing the
  native confirm dialogs). At zero the action fires; Cancel aborts and re-enables the buttons — a
  safety net against a misclick on a hard-to-undo action.
- **Confirmed (Matt): the unit boots when power is unplugged and restored** — so cycling the outlet
  is a reliable boot, the hard-to-reach physical power button is a non-issue, and after a Shut down
  you power back on by replugging (or a smart plug). Recorded in §10; the exact Auto-Power-On
  default/label is still bench-TBD (§19). (Matt, 2026-06-13.)

### 2026-06-13 — Terminology nailed down; control-panel copy pass; onboarding reference
- **Canonical vocabulary (user-facing):** **frame** = the physical device; **control panel** = the web
  UI you control it from; **screen** = the display surface; **display** = the `/display` kiosk page only.
  Swept the control panel + Setup Guide to match — e.g. header **"Blank panel" → "Blank screen"**, restart/
  update status copy now says "frame" (the device) not "panel," and "Reach this panel" → "Reach the control
  panel." (Engineering prose in this doc still says "panel" for the physical LCD where that's the precise
  hardware term — the scheme governs user-facing copy.)
- **Power-card copy tightened** (Matt): Restart note → **"Restarts the frame."** (dropped "and brings it
  right back" — restart already implies the return); Shut down note → **"Turns off the frame."** Button
  stays **"Shut down"** (two words — it's the verb, matching macOS/Windows).
- **Wi-Fi card:** removed "no keyboard needed" (don't tell users what they don't need); "frame" throughout.
- **Onboarding reference recorded (§11):** Matt shared the stock Infinite Objects Wi-Fi flow; logged it
  plus our refinements (QR codes on the setup screen, plain labels, pick-from-scanned-list, two-screen
  confirmation, recovery/self-heal, AP naming) as the Phase-2 design. Build none now. (Matt, 2026-06-13.)

### 2026-06-13 — Hardware stubs (Restart / Shut down / Wi-Fi); Phase 1 feature-complete
- **Settings → Power card:** **Restart** ships **live** — an app-level soft-restart through the
  supervisor (exit → relaunch, the §15 path), so it genuinely works browser-only with no hardware
  and is identical to what systemd will run on the device. **Shut down** is a visible-but-inert
  **stub** (can't/mustn't power off the dev Mac); Phase 2 wires a real OS power-off. Restart was
  made live rather than a stub (Matt's call) because the supervisor already made it durable and
  free — the old "inert stub" note predated the supervisor.
- **Settings → Wi-Fi card:** an explanatory **stub** for the first-run OpenObject-Setup AP +
  captive-page flow (§11; Phase 2), plus a **real** "reach this panel" helper showing the live LAN
  address(es) and the `openobject.local` name.
- **Backend:** `GET /api/system` (supervised flag, port, mDNS name, LAN addresses),
  `POST /api/system/restart` (live under the supervisor; reports `needsManualRestart` under
  start:direct), `POST /api/system/shutdown` (inert stub + message). `/healthz` gained a per-process
  **`boot`** id so the panel can confirm a plain restart — unchanged version — actually bounced. All
  owner-initiated, none in the playback path.
- **Phase-2 power note recorded:** a full **device reboot** (`systemctl reboot`) and real
  **power-off** (`systemctl poweroff`) are easy on the Linux device; with BIOS Auto-Power-On a
  power-off returns on next power, so a true "off" is the outlet/smart plug (§10).
- **Phase 1 is now feature-complete on macOS** — server, library/upload, control panel, display +
  behaviors, progressive sync, sleep hours, self-update, and these stubs. Remaining work is
  hardware/Phase 2. (Matt, 2026-06-13.)

### 2026-06-13 — Self-update UI redesign + control-panel layout
- **Software Update card decluttered to the traditional shape** (Matt's review): a clear
  **Current version** line — `version · date · commit` (e.g. `0.1.0 · June 13, 2026 · a1b2c3d`,
  the commit a small unlabeled link to GitHub) — then **Check for updates**, and on an available
  update a plain-English recap of what's in it, a **What's new ↗** link to the GitHub diff, and
  **Update & Restart** / **Not now**. The version number alone doesn't change every update, so the
  **build date** is the human "it updated" signal and the short **commit** the precise one (covers
  two-updates-in-a-day); the jargon (`commit`, `tracking main`, raw hashes in the body) is gone.
  New backend fields feed it: commit `date` (`git %cs`) and `repoUrl`/`compareUrl` derived from the
  origin remote (suppressed for non-web remotes).
- **Update channel toggle removed from the UI** — track the latest on `main` only. The channel
  machinery stays in the backend (`update_channel`, `PUT /api/update/channel`), so a plain "vetted
  releases" choice can return if/when we publish tagged releases (pairs with going public).
  "Stable releases" was dropped from the UI because we have none yet — it would only read "no
  releases yet."
- **Section headers Title-Cased** (Sleep Hours, Software Update) via a shared `.section-title`.
- **Control-panel layout: tabs moved to the top; the upload dropzone now lives inside the Library
  tab** (no longer pinned above all tabs). Uploading is a Library action, so seeing it from
  Rotation/Settings was odd. **This reverses the earlier "upload pinned above the tabs" call** (see
  the Rotation-curation entry below). A "drop a file anywhere → Library" convenience was considered
  and declined — keep it simple. (Matt, 2026-06-13.)

### 2026-06-13 — Self-update from GitHub built (§15)
- **Self-update shipped, browser-driven end to end (§15).** The **Settings** tab gains a
  **Software update** card: it shows the running version + commit + tracked branch, a **Check
  for updates** button (git fetch + compare to the channel's target), and — when a newer,
  fast-forwardable version exists — an **Update & restart** button that pulls
  (`git merge --ff-only`), reinstalls dependencies **only if the manifest changed**, and
  relaunches. `/healthz` now also reports the running **commit**, which the panel polls to
  confirm the new version came back up. Everything happens over the browser — **no hardware
  access** — which is the whole point of building it now.
- **Restart mechanism = a tiny supervisor (`player/supervisor.js`).** `npm start` now runs the
  supervisor; it spawns `node server.js` and relaunches it when the player exits with restart
  code **75** after an update. `npm run start:direct` runs the server alone (no auto-relaunch —
  self-update then asks for a manual restart). This is the Phase-1 stand-in for the device's
  service manager; **Phase 2 swaps it for a systemd unit** (`Restart=always`), the player side
  unchanged. The launch config now points at the supervisor.
- **Guardrails (all verified):** **fast-forward only** — a diverged checkout (local commits)
  refuses with a clear message and changes nothing, never a force-reset; **runtime data
  untouched** — `player/data/` + uploads are gitignored, invisible to the pull; **offline-safe**
  — a failed fetch reports gracefully and never touches playback; **owner-initiated only**,
  never automatic, never in the playback path. Art still never touches the repo (§8).
- **Channel setting** (`update_channel`): track **`main`** (default) or **tagged releases**
  only (§12). New routes: `GET /api/update` (instant, no-network status), `POST /api/update/check`,
  `POST /api/update/apply`, `PUT /api/update/channel`.
- **Tested end-to-end on macOS without real upstream commits** via a throwaway bare-clone
  "fake origin" sandbox (snapshot the working tree → bare repo → work checkout → push synthetic
  commits): proved no-update → update → fast-forward + restart (`/healthz` commit flips) →
  divergence refusal, plus the offline and not-a-git-checkout paths. The sandbox is disposable
  and never touches the real repo or GitHub. (Matt, 2026-06-13.)

### 2026-06-13 — Sleep hours built (+ manual Blank)
- **Sleep hours shipped (§13):** up to **two daily blank windows**, each with an **enable
  checkbox** (work + night); times on a **12-hour clock with an AM/PM** segmented toggle,
  wrap-past-midnight supported with an auto **"overnight"** tag. Off by default.
- **Manual "Blank panel"** toggle added to the header — art off on demand, independent of the
  schedule (the parked Blank/Pause companion; it lives in the header we said we'd revisit).
- **Sleep screen** mirrors the boot/idle mark exactly — same size/placement, **dimmed, no
  caption** — with a slow **pixel-shift** (~90 s) for burn-in insurance. Pixel-shift was chosen
  over a periodic fade (the standard technique, sufficient on its own; Matt's call). Playback
  stops while asleep and resumes on wake.
- **Server-computed `asleep`** (from settings `sleep_ranges` + `manual_blank`) is returned in
  `/api/display`; `PUT /api/settings` gained validated `sleepRanges` + `manualBlank`. No DB
  change — both are key/value settings. Phase 1 blanks in software; backlight dimming is a
  Phase 2 hook. (Matt, 2026-06-13.)
- **Control panel reorganized to three tabs — Library · Rotation · Settings.** Sleep hours
  moved into the new **Settings** tab (its future home for self-update, restart/shutdown,
  Wi-Fi onboarding); the **duration/order** bar moved into the **Rotation** tab (it governs how
  the rotation cycles). The top of the page is now just upload + tabs. Sleep mark dimmed from
  0.3 to **~0.2**. (Matt, 2026-06-13.)

### 2026-06-13 — Logged: Web/HTML art pieces (future seam, §17)
- **Logged a future enhancement — a "HTML" content type** (working name): add a **live web
  page** (generative/interactive `index.html`, e.g. Arweave-hosted) as a piece via
  **paste-URL + optional name + special functions**, handled through a **curated by-name
  registry for featured collections** (first target: Bryan Brinkman's *"Azulejo Galo"* and
  its in-page "Toggle Rotation" control). It's a new render kind (`web`, iframe/webview) and a
  §8 source-layer seam — distinct from the on-chain/NFT seam (which resolves to a media file).
  **Not built**; captured in §17 with its constraints (Fit/Fill semantics, §9 local-first
  tension, cross-origin control → likely Phase-2 kiosk, sandboxing). (Matt, 2026-06-13.)

### 2026-06-13 — Rotation curation (membership + manual order); settings bar redesign
- **The Rotation is now a curated subset, not the whole Library** — completes the §7
  Library/Rotation/Pin model. Two new `library` columns, `in_rotation` (default 1) and
  `position`, added by an **idempotent PRAGMA-guarded migration** that backfills existing
  rows to in-rotation in upload order, so prior behavior is unchanged. New uploads
  **auto-join** at the end of the order — keeps the zero-effort "everything I upload plays"
  default; unwanted pieces are removed in the Rotation tab. (Matt, 2026-06-13.)
- **API:** `PATCH /api/library/:id` now also accepts `inRotation`; added `GET /api/rotation`
  (curated members in order, *not* pin-collapsed — that's display-only) and
  `PUT /api/rotation/order { order:[id,…] }` (renumbers members 0..n-1 in one transaction).
- **Pin now overrides Rotation membership** (§7 "overriding the cycle"): `/api/display`
  resolves the pinned piece from the **full Library** and collapses to it even if it isn't
  in the Rotation — fixes the case where a pinned non-member would vanish once
  Rotation ≠ Library. `display.js` is unchanged (its own collapse became a harmless no-op).
- **Control panel reorganized into two tabs — Library and Rotation** (Matt's "separate page
  you toggle to, then back" call, over reordering inside the Library grid). Library tab:
  each card gains a corner **add/remove-from-rotation** toggle. Rotation tab: the ordered
  list, reorderable by **drag *and* ↑/↓ arrows** (arrows are the touch-safe path on
  iPhone/iPad, where native drag is unreliable), **✕** to remove; a hint notes the order
  drives Sequence and is cosmetic under Shuffle. Rotation-list thumbnails **honor each
  clip's Fit/Fill** so they match the Library cards and the panel. Control icons (grip,
  arrows, remove) are **inline SVG — no webfont**, so the panel works on an offline frame.
  Upload + settings stay persistent above the tabs.
- **Settings bar redesigned (Option A of three mockups):** a −/+ **stepper** on the
  duration, **segmented** unit (sec/min/hr) and **segmented** order (Sequence/Shuffle)
  replacing the dropdowns. (Matt picked Option A, 2026-06-13.)
- **Sleep-screen direction captured for §13** (design intent; Sleep Hours not built yet).

### 2026-06-12 — Display rotation engine; global equal-time duration
- **Duration is one global, equal-time setting for every piece** — no per-clip duration
  (revises §7/§12). Stills hold for it; animated + video loop to fill it; a clip longer
  than the duration is cut when the timer advances; video always loops. Dropped the
  per-clip `duration_ms`/`video_full` columns from the `library` table. (Matt, 2026-06-12.)
- **/display rotation engine built** (§6, §7, §9): renders the Rotation (v1 = the whole
  Library, upload order) edge-to-edge with per-clip Fit/Fill, crossfades between pieces,
  Sequence/Shuffle, always muted. New uploads/deletes, Fit/Fill flips, and
  duration/order changes fold in live via a ~5s poll — no loop restart (§9 progressive).
- **Control panel** gains a global Settings bar (duration + order) and a per-clip
  Fit/Fill toggle. New endpoints: `GET/PUT /api/settings`, `GET /api/display`,
  `PATCH /api/library/:id {fit}`.
- **Pin** (hold one piece permanently — collapses the rotation to it, resumes on unpin)
  and **duration units** (seconds / minutes / hours) included. New endpoints
  `PUT /api/pin/:id` + `DELETE /api/pin`; deleting a pinned piece clears the pin.
- **Rotation default = the whole Library**; new uploads auto-join. Curation
  (remove-from-rotation, reorder) comes next. (Matt, 2026-06-12.)
- **Web-app favicon + apple-touch-icon** added (white-bg logo at 16/32/180 px) — the
  apple-touch-icon gives a proper home-screen icon for phone/iPad control.
- **Random rotation order removed** — Shuffle already gives random order with no
  near-term repeats; pure Random (independent pick, can repeat back-to-back) was an odd
  fit for an art frame. Modes are now **Sequence / Shuffle** only. (Matt, 2026-06-12.)

### 2026-06-12 — Upload + Library shipped; node:sqlite locked
- **SQLite library chosen: Node's built-in `node:sqlite`** (over better-sqlite3) — zero
  native deps, no build step, best for revivability; all DB access is contained in
  `player/src/db.js`, so a later swap stays local. Its lone startup ExperimentalWarning is
  silenced surgically (only that one line; every other Node warning still prints). (Matt's
  call, 2026-06-12.)
- **Web upload + Library built** (§7, §8): drag/tap multi-upload via `multer` (pure-JS,
  no native build), stored **byte-for-byte** under `player/uploads/`; a format gate by
  extension accepts JPEG/PNG/GIF/AVIF/WebP/MP4/MOV/WebM and **skips the rest silently** (§6).
  Adds a `library` table + `GET/POST/DELETE /api/library` (delete removes the row *and*
  the file).
- **WebM added to the v1 video formats** (after MOV): open, royalty-free VP8/VP9/AV1 —
  always compiled into Chromium, so it's the most reliably-playable video on a minimal
  Linux frame (H.264/MP4 may need a codec package there). Same `kind: video` loop path,
  so trivial to add. List order also set to AVIF before WebP. (Matt, 2026-06-12.)
- **`/` is now the control panel** (was a redirect to `/display`); the kiosk stage stays
  at `/display`. The display still renders only the Rotation — uploads fill the Library;
  the rotation engine that puts them on the panel is the next checkpoint.

### 2026-06-12 — Self-update from GitHub (Phase 1)
- **OpenObject updates itself from its GitHub repo via the control panel** (Check for
  updates → Update & restart). The player runs as a git checkout; update =
  `git pull --ff-only` + dependency reinstall + relaunch. Fast-forward only (refuses on
  local divergence); runtime data (`player/data/`, uploads) is gitignored and untouched;
  owner-initiated, never automatic, never in the playback path. Channel setting: track
  `main` (default) or tagged releases. (§15, §12)
- **Placed in Phase 1, not Phase 2:** the check / compare / pull / relaunch runs entirely
  on the dev Mac and is built + tested there now; only the production restart shim
  (systemd on the device) is Phase 2. It lands after the core control panel, since the
  update UI lives there. (Requested by Matt 2026-06-12.)

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

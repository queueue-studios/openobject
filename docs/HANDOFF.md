# OpenObject: Build & Handoff Specification

> **Document type:** Implementation spec for Claude Code.
> **Status:** Running on real hardware. The web app (Phase 1) plus the Debian and Chromium-kiosk installer (Phase 2B) are built and verified on an actual XXL frame, with over-the-air self-update working. What's left is later milestones (single-file release image, Wi-Fi onboarding AP, real restart/shutdown). See §20 for the decision log.
> **Local project root:** `~/Code/OpenObject`
> **GitHub repo:** `mattonchain/openobject`, **public** since 2026-06-14 (created private 2026-06-11). Claude drives all git operations on Matt's approval.
> **Website:** https://openobject.io

---

## 1. What OpenObject is

OpenObject is replacement software for the **Infinite Objects XXL** digital art frame, a 26" **square (1:1)** display. The frame originally ran the "White Walls" software (an Android kiosk app that rendered on-chain NFT art). That original setup is no longer reliable: the backend services it relied on have wound down.

The XXL's display is driven by a small **fanless mini PC mounted on the back of the panel**. OpenObject wipes that mini PC and turns it into a clean, self-hosted local art frame: it displays local image and video files, is controlled entirely from a web page the owner opens in any browser, and depends on no external service.

**Two design commitments shape everything:**

1. **Self-contained on the player.** The mini PC is the always-on brain. The owner's Mac/phone are just places files come *from* and a browser to control it; the frame never depends on them to keep running.
2. **Revivable by the next owner.** This is meant to be a shareable kit so *other* stranded XXL owners can revive their units. Design decisions favor "anyone can follow the guide" over "convenient for the original builder only."

---

## 2. Hardware target

The mini PC is a **MeLE Quieter 3Q** (confirmed from the unit's label; the BIOS reports board name **`XXL`**, an Infinite Objects custom badge on the same N5105 platform).

| Attribute | Value |
|---|---|
| Model | MeLE Quieter 3Q (BIOS board name `XXL`) |
| CPU | Intel Celeron **N5105** (Jasper Lake / "JasperLake ULX"), 2.00 GHz, **x86-64**, _bench-confirmed 2026-06-13; earlier "N5100" was wrong_ |
| RAM | 8 GB LPDDR4x _(typical config; not yet confirmed at bench)_ |
| Storage | **~128 GB eMMC**, confirmed from Linux as **116.5 GiB** at `/dev/mmcblk0` (2026-06-13): EFI `p1` 512 MB + ext4 `p2` 116 GB, plus 4 MB `mmcblk0boot0/1`. UEFI device id `A3V012`. _(The earlier "~256 GB" came from the Android storage screen and was wrong, `lsblk` is authoritative; the original "128 GB" was right.)_ |
| Expansion | microSD slot (pressure valve for larger libraries) |
| Networking | Onboard Wi-Fi, Intel Jasper Lake **CNVi** `[8086:4df0]` (`iwlwifi`) + **Gigabit Ethernet** Realtek RTL8111/8168 `[10ec:0123]` (`r8169`), _both confirmed 2026-06-14_ |
| Display panel | 26" **square (1:1)**, **1920×1920** native, over HDMI (Intel JasperLake UHD / `i915`; the iGPU also advertises 1920×1080 fallback modes), _confirmed 2026-06-14_ |
| Power | 12 V / 2 A barrel jack |
| FCC TX ID | PD99560D2 _(use to confirm Wi-Fi module / Linux driver at bench)_ |
| Serial | 8ICH4F310P530467 |
| MAC | 00CE39D53121 |

**Ports on the outward-facing edge:** 1× USB-A 3.0, 3.5 mm audio, microSD, 2× HDMI, 1× USB-C (DP-capable), 1× Gigabit Ethernet, barrel power.

**Critical hardware facts for the build:**

- This is a **normal x86 PC with a UEFI BIOS**, not an Android appliance. Infinite Objects installed **Ubuntu Linux** and runs the original "White Walls" player as an **Android app inside Waydroid**, a **LineageOS Android 11** container (`lineage_waydroid_x86_64`, build `RQ3A.211001.001`) on the Linux host, which is *why the original UI looks like Android*. Underneath it boots like any PC and runs Linux from a USB stick. **Confirmed at bench (2026-06-13):** UEFI firmware (AMI Aptio `ML_JPL1 V1.0.0 x64`, core 2.22.1282), **`Del`** enters Setup, **no BIOS password**, **Secure Boot off**, boot mode **UEFI**; the factory boot entry is `ubuntu (eMMC A3V012)`.
- The mini PC connects to the 26" panel via a captive **HDMI** lead (video) plus a **USB-C** lead (power and/or control). **This cabling is not touched.** OpenObject is a software reflash; the player↔panel wiring stays exactly as the vendor built it. After Linux is installed, video outputs over the same HDMI the panel already uses.
- When wall-mounted, only **one USB-A port is realistically free**, and the physical power button is hard to reach. Both constraints are solved in §4 and §10.

---

## 3. Operating system

**Minimal Debian (stable), UEFI**, locked 2026-06-14 (see the build note at the end of this section). Selection criteria that drove it:

- Recent-enough kernel that the **onboard Wi-Fi works out of the box** (verify the module via FCC ID / `lspci`/`lsusb` at bench; keep a known-good USB Wi-Fi dongle as the only fallback, it would ride in the hub).
- Can run **Chromium in kiosk mode** as the display surface (see §6).
- Can run a small local web server for the control panel and the display page.
- mDNS via Avahi so the panel is reachable at `http://openobject.local`.
- Samba available **only** if the optional SMB pull-source is enabled (see §8); not required for the default web-upload flow.

The OS image should boot directly into the OpenObject display with no desktop, login, or visible Linux chrome.

> **Bench note (2026-06-13):** the factory unit already runs **Ubuntu** on this exact hardware (N5105 iGPU, the square HDMI panel, onboard Wi-Fi, the USB hub), so a Debian-based install is low-risk, graphics, panel, and networking are all known-good under mainstream Linux. The factory stack is heavier than ours (Ubuntu → Waydroid container → Android → White Walls) and boots slowly (~1 min to art); our native Node + Chromium-kiosk path should boot markedly faster.

**Built 2026-06-14 (Phase 2B), installer stack locked + built (Mac side):**
- **Base:** minimal **Debian stable** (UEFI; no desktop), installed by the standard Debian
  netinst, which also wipes the eMMC and joins Wi-Fi. Our `installer/install.sh` provisions
  OpenObject on top, idempotent, re-runnable.
- **Display surface:** **`cage`** (a Wayland *kiosk compositor*: one fullscreen app, cursor
  hidden, no blanking) running **Chromium `--kiosk`** at `http://localhost/display`. No X, no
  window manager, no display manager. (X11 + Openbox is the documented fallback if cage
  misbehaves on the N5105 iGPU, see `installer/README.md`.)
- **Services:** **systemd** runs the player and the kiosk (replacing `player/supervisor.js`,
  §15). **Avahi** advertises `openobject.local`; **NetworkManager** owns Wi-Fi (the foundation
  for the §11 setup-AP). Intel iGPU + VA-API drivers and `libavcodec-extra` are installed for
  hardware decode (WebM is always safe; the codec package widens MP4/H.264 support).
- The build tooling lives in `installer/` (`install.sh`, `systemd/`, `kiosk/`, `README.md`).

---

## 4. Access & reflash procedure (one-time bench/in-place session)

This is the procedure to convert a stock XXL to OpenObject. It is performed once. The unit can stay wall-mounted; the outward-facing port edge remains reachable.

> **⚠️ Caution, do NOT remove the two screws above the MeLE.** On the back of the XXL, the two screws on the bracket/plate directly **above** the MeLE mini PC retain captive nuts on the *inside* of the chassis. Loosening or removing them drops those nuts inside the unit, and recovering them requires a **near-full disassembly and reassembly** of the XXL. They are **not** part of this procedure, leave them alone.

**Access hardware** (the owner-supplied kit, exact models recorded in the Setup Guide, §16):
- **Left-angle** USB-A extension from the single free port out to a reachable spot, then a USB hub on the end (one port can't host both the installer stick and a keyboard). The **left** angle is deliberate: it routes the cable clear of the frame controller's **power socket**, which sits immediately beside that USB port and must stay reachable to seat the power cord. (Confirmed part: CableCreation **CC0516**, see §16.)
- USB keyboard (a keyboard+touchpad combo on one dongle is ideal).
- USB flash drive (≥16 GB) for the Linux/OpenObject installer.
- External USB drive (≥128 GB; small USB SSD ideal) for the pre-wipe backup image.

**Procedure:**

1. **Connect** the hub to the free USB-A port; attach keyboard + installer flash drive.
2. **Enter the BIOS** at power-on by tapping **`Del`** _(confirmed 2026-06-13)_. The IO splash uses **Quiet Boot**, so no "press a key" prompt appears, tap `Del` repeatedly from the instant you power on, during the black screen (that's POST). The panel then shows the BIOS screen over HDMI. _(On a Logitech K400, `Del` is a direct key; the F-keys are Fn-shifted.)_
3. **Set boot order / boot menu** to boot from the USB flash drive. _(With the stick inserted it appears as a new boot option; use a one-time boot menu, likely `F7`, or **Save & Exit → Boot Override**, or set Boot Option #1. Confirm the boot-menu key with the stick in hand.)_
4. **Auto power-on, nothing to set.** _(Confirmed 2026-06-13:)_ this BIOS exposes **no** "Auto Power On / Restore AC Power Loss / State After G3" toggle (checked `Chipset → PCH-IO Configuration`), and the unit already boots on its own when power is applied, auto-on is the firmware default. So it boots whenever it receives power, no button press, nothing to enable (see §10). _(If a future unit doesn't auto-boot, the only place an ODM might hide it is `Advanced → Customer Exclusive Functions`.)_
5. **Boot the live USB.**
6. **BACK UP FIRST, image the existing eMMC** to the external drive (full-disk image). This preserves the original **Ubuntu + Waydroid (White Walls)** install in case the owner ever wants it back *while the vendor's servers still exist*. This is the clean, ADB-free way to capture it. **Do this before any wipe.**
7. **Install OpenObject** to the eMMC. Two stages (full runbook: `installer/README.md`):
   **(a)** run the standard **Debian stable netinst**, wipe `/dev/mmcblk0`, choose a *minimal*
   system (untick the desktop; keep "standard system utilities"), set hostname `openobject`,
   join Wi-Fi. **(b)** seed the OpenObject checkout to `/opt/openobject` (from a `git bundle` on
   a USB stick) and run **`sudo bash /opt/openobject/installer/install.sh`**, it installs Node
   22, Chromium + cage, Avahi, NetworkManager, the systemd units, and reboots into the kiosk.
8. **Verify on the panel** before considering it done: the display comes up edge-to-edge at
   `/display`, `http://openobject.local` is reachable over Wi-Fi, an uploaded clip plays,
   **Restart** bounces the player, and an unplug/replug auto-boots back to the display.

> **Recorded at bench (2026-06-13):** BIOS-entry key = **`Del`**; there is **no** "auto power on" setting (auto-on is the firmware default, see step 4); eMMC = **~128 GB** (`/dev/mmcblk0`, **116.5 GiB** confirmed from Linux), UEFI id `A3V012`.

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

**Why the browser engine:** the owner's real-world library is a polyglot of formats, AVIF (incl. animated), animated WebP, GIF, PNG transparency, plus MP4/MOV/WebM. A browser engine decodes all of these natively with one renderer, and `fit`/`fill` plus video looping fall out of standard CSS/HTML. A native image viewer + separate video player would require bolting on a separate decoder for half these formats and special-casing the animated ones.

**Supported formats (v1):**

| Category | Formats | Behavior |
|---|---|---|
| Stills | JPEG, PNG | Hold for set duration. PNG transparency renders against **black**. |
| Animated | GIF, AVIF, WebP | Animate and **loop to fill** their set duration. **Never freeze on frame one.** |
| Video | MP4, MOV, WebM | **Always loop.** "Full length" or fixed duration (see §7). No audio (§12). |

**Explicitly ignored (v1):** HEIC, SVG (deferred, renders unpredictably at arbitrary canvas sizes), PSD, CR2 (raw), GLB (3D model), and all OS/working-file noise (`.DS_Store`, `.docx`, `.xlsx`, etc.). The player simply skips unsupported files, **no conversion step on ingest** (uploads stay byte-for-byte).

**Display surface, edge-to-edge, no chrome.** The display page is a full-panel **black stage** (`100vw × 100vh`; zero margin, padding, border, scrollbars, or UI). Media renders to the **physical edges of the panel**; OpenObject adds **no decorative frame or border, ever**. In Fit mode the surrounding black is bare stage, not a frame.

**Fit vs Fill (per-clip; v1 default is _Fit_ / original aspect ratio):**

- **Fit** = `object-fit: contain`, entire image visible at its **original aspect ratio**; black fills the leftover. Nothing cropped. **This is the default.**
- **Fill** = `object-fit: cover; object-position: center`, image scaled to cover the full square, cropping the overflow **symmetrically from the center**: left/right trimmed for landscape, top/bottom for portrait. The center is always kept.

The square (1:1) panel makes this choice matter more than on a normal screen, because almost nothing displayed is square, hence per-clip control. **v1 uses center-crop only**; adjustable crop position (e.g. bias toward the top to preserve faces) is a documented future enhancement (§17).

---

## 7. Content model

**Library + Rotation + Pin.**

- **Library**, everything ever uploaded; stays on the player's local storage.
- **Rotation**, the subset currently cycling on the panel, in a chosen order. Order is **Sequence** or **Shuffle**:
    - **Sequence**, plays in the order you set, looping.
    - **Shuffle**, a randomized *pass*: every clip plays once before any repeats, then reshuffles. Good coverage, no near-term repeats.
- **Pin (a.k.a. "permanent"/"hold")**, optionally elevate **one** clip to display permanently, overriding the cycle until unpinned. Supports the workflow "upload several, then manually promote whichever one to permanent," and the degenerate case "I just want one image up forever."

Uploading **adds to the library**. A "daily refresh" habit is achieved by curating which library items are in the rotation (clearing/selecting), so both mental models, daily-replace and growing-curated-library, are served by the same structure. _(**Confirmed 2026-06-11:** library+select, not hard replace-on-upload. **Built 2026-06-13:** per-item add/remove toggle in the Library tab; Sequence order user-arranged by drag or ↑/↓ in the Rotation tab; §20.)_

**Duration, one global, equal time for every piece (confirmed 2026-06-12).**

- A **single global duration** applies to **every** piece in the rotation, equal time per content piece. There is **no per-clip duration**.
- **Stills** (JPEG/PNG) hold for the duration.
- **Animated** (GIF/WebP/AVIF) and **video** (MP4/MOV/WebM) **loop to fill** the duration: a piece shorter than it repeats; a piece **longer** than it is cut off when the timer advances. **Video always loops; it never freezes on a last frame.**

---

## 8. Source layer (pluggable)

Design the source layer as a **clean interface**: *a source provides files to the library.* The uploader is not hard-wired as the only way files can arrive. This is good architecture regardless, and it is what lets future sources (§17) slot in without a teardown.

**v1 sources:**

- **Web upload (default).** Open the control panel in a browser → drag art onto the page, or tap to choose files → it lands in the library. Works identically from Mac, iPhone, iPad, Windows. **No mounting, no credentials.** This is the everyday path.
  - **Upload guards (added 2026-06-16).** Each file is size-capped (default **512 MB**, env `OO_MAX_UPLOAD_MB`), with up to `OO_MAX_UPLOAD_FILES` (default 50) per request; an oversize file is refused with a clear message (HTTP 413) and no partial file is left on disk. Before accepting any upload the player checks free space and refuses when the disk would fall below a safety margin (env `OO_MIN_FREE_MB`, default **2048 MB**, HTTP 507), so no client on the LAN can fill the eMMC and wedge the frame.
- **Pull from a network share (optional).** For power users who'd rather point at an existing folder on their machine. Player connects to an SMB share (Samba speaks both macOS and Windows file sharing) and syncs from it. Requires address + credentials in the control panel.

**Not a source / explicitly out of scope:** Git/GitHub is **not** part of the content path in any form. GitHub is used solely for **source-code management and distribution** of OpenObject itself (§15). Art never touches the repo.

---

## 9. Storage & sync model

**Progressive sync, full local mirror at rest, buffered fallback only when forced.**

- **Progressive sync (first run):** grab the first few clips, **start the rotation as soon as the first clip lands**, then continue pulling the rest into local storage in the background while the panel is already showing art. The display waits only for the first clip, not the whole library. The rotation must **fold in newly-arrived clips gracefully without restarting or stuttering** the loop.
- **Full local mirror (steady state):** once synced, the entire library lives on the eMMC and **playback is always local**, a 30 MB clip loads from local storage in a fraction of a second. The network is used **only when the library changes** (add/remove). No clip is ever downloaded or deleted at display time. There is **no per-clip download→display→purge loop**, that design is explicitly rejected because it puts Wi-Fi in the playback path and churns the eMMC.
- **Capacity:** the target library (hundreds of ~30 MB clips ≈ 3–30 GB) fits comfortably in ~100+ GB of free eMMC after a slim Linux install. microSD expands it further.
- **Buffered mode (optional fallback):** engages **only** when a library genuinely exceeds free storage (e.g. a future owner with a 300 GB 4K archive). It is **not** strict per-clip purge; it is a **prefetch buffer with least-recently-shown eviction**, keep the next N clips staged ahead of playback, evict oldest-shown only under space pressure, so the network is never what playback waits on. Matt's default never engages this; it exists for the next-owner kit.

A single **storage-mode setting** governs this: default **"full sync"**, with **"buffered"** offered only when the library outgrows the disk.

---

## 10. Power handling

The physical power button is hard to reach when wall-mounted. This is fully solved in software/BIOS:

- **Auto Power On (BIOS):** enabled during reflash (§4). The unit boots the moment it receives power. Power control becomes the wall outlet (or an optional smart plug). Also means the frame **self-recovers after a power blip** instead of waiting for a button press.
    - **Confirmed (Matt, 2026-06-13):** this unit **boots when the power cord is unplugged and replugged**, so cycling the outlet reliably boots it and the hard-to-reach physical power button is a **non-issue**. After a **Shut down**, you power the frame back on by replugging (or toggling a smart plug). **Resolved at bench:** there is **no Auto-Power-On toggle** in this BIOS (checked `Chipset → PCH-IO Configuration`, no "State After G3" / "Restore AC Power Loss"); auto-on is the **firmware default**, which is exactly this replug-boot behavior. Nothing to set.
- **Soft restart / reboot / shutdown (web UI):** the control panel exposes **Restart** (the player), **Reboot** (the whole device), and **Shut down**, initiated from the owner's browser. Handles all intentional reboots without reaching behind the panel.
- **Hard lockup (rare):** power-cycle the outlet; an optional ~$15 smart plug makes this a phone tap. Not required.

**Built 2026-06-13 (§20).** The control panel's **Settings → Power** card ships **Restart**, **Reboot**, and
**Shut down**. **Restart is real now**: an app-level soft-restart via the supervisor (exit →
relaunch, the same path as self-update, §15), so it works browser-only with no hardware and behaves
identically once systemd runs it on the device. **Reboot** (`systemctl reboot`) and **Shut down** (`systemctl poweroff`) are real on the installed
Linux frame, carried out by systemd via a one-time polkit grant the installer adds for the
`openobject` user; off-device (the dev Mac, which must never be powered off) they stay inert stubs
that only return a message. Per the
Auto-Power-On point above, a real power-off returns when power is restored, so a true "stays off"
is the outlet / smart plug.

---

## 11. Network & first-run onboarding

A fresh, wall-mounted box has no art and isn't on Wi-Fi yet, but the control panel is reached *over* Wi-Fi. Solve the chicken-and-egg with a **self-broadcast setup network** (the standard headless-device pattern; keyboard-free and next-owner-friendly):

1. On first boot with no known network, the player **broadcasts its own temporary Wi-Fi network** (e.g. `OpenObject-Setup`).
2. The owner joins it from a phone/laptop; a **captive setup page** appears.
3. They pick their home network and enter the password.
4. The player **switches over** to the home network and the setup AP shuts down.
5. This **self-heals** if home Wi-Fi credentials later change (box falls back to setup AP).

**Reaching the control panel:** `http://openobject.local` (mDNS), works natively on Mac/iPhone. The setup page also **displays the raw IP** as a fallback (e.g. for Windows clients without mDNS).

**Wired option:** the free Gigabit Ethernet port is a fully supported bonus, but **Wi-Fi is the baseline**, the kit must not require running a CAT5 cable, since the next owner may not be able to.

**Built 2026-06-13 (§20, Phase-1 stub).** The control panel's **Settings → Wi-Fi** card explains the
first-run onboarding flow above; the setup AP + captive page themselves are **Phase 2** (they need the
device's networking). The card also shows **how to reach the control panel now**, the live LAN
address(es) (`http://<ip>:<port>`, from `GET /api/system`) plus the `openobject.local` name that
resolves on the installed frame, which is real and useful in Phase 1.

**Reference, observed Infinite Objects onboarding (2026-06-13), and our refinements.** Matt captured
the stock XXL's Wi-Fi setup; it's a proven flow worth building on. Observed: the frame's screen shows
**two QR codes**, (1) a Wi-Fi-join QR for its setup AP (`IOXXL-<id>`, WPA password `infinite`), and
(2) a URL QR to a config page at `ioxxl.local`. On the page you enter **SSID + Pass Phrase → Connect**;
the phone then shows "configuration in progress, wait for confirmation on the screen," and the frame
confirms "Successfully Connected… searching for updates and rebooting."

Refinements to adopt for OpenObject (Phase 2, build with the hardware):
- **QR codes on the frame's setup screen**, the biggest win. The branded boot/idle screen, in its "no
  network yet" state, *becomes* the setup screen: mark + a **join-AP QR** (one-tap join, no typing) + an
  **open-config QR** (one tap to the captive page) + a manual fallback (network name, password, URL).
- **Plain labels** on the config page, "Wi-Fi network name" and "Password", not "SSID" / "Pass Phrase".
- **Pick the network from a scanned list** rather than typing the SSID (typo-proof; manual entry as a
  fallback for hidden networks).
- **Two-screen confirmation**, when the frame leaves its own AP to join home Wi-Fi, the phone loses
  contact with it, so success is confirmed on the **frame's screen** ("Connected ✓") while the phone
  shows "applying, watch the frame."
- **Recovery line + self-heal**, on failure the setup AP returns; tell the user to re-join it and retry.
- **AP naming/password**, `OpenObject-<id>` (a short unique suffix so two frames don't collide); open
  network vs. a QR-encoded password is a Phase-2 call (the join-QR makes a password basically free).

The stock screens themselves are reference only, captured here as learnings, not committed (art and
photos never enter the repo, §8). Build none of this in Phase 1.

---

## 12. Settings & defaults

| Setting | v1 default | Notes |
|---|---|---|
| Audio | **Muted, always** | Silent art on a wall. Future: optional global "allow audio" toggle. |
| Control-panel access | **Open on LAN**, optional password (built 2026-06-16) | Off by default (no login friction). When set in Settings it gates the control panel + every mutating API; the kiosk display stays open. HMAC-signed httpOnly cookie session, scrypt-hashed password, no new dependency. |
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

**Built 2026-06-13.** Up to **two daily windows**, each with its own **enable checkbox**,
covering both "I'm at work" and "I'm asleep." Times are entered on a **12-hour clock with an
AM/PM toggle** and may cross midnight (an auto **"overnight"** tag flags a window that wraps).
A manual **"Blank panel"** toggle in the control-panel header turns the art off on demand,
independent of the schedule, the companion to scheduled sleep, and the answer to "how do I
stop the display right now?". While asleep, **playback stops** and the panel shows the **sleep
screen**: the same boot/idle mark at the **same size and placement, dimmed (~0.05 opacity) and
with no caption** underneath. To rest the panel it does a slow, imperceptible **pixel-shift**
every ~90 s (the standard anti-burn-in technique, chosen over a periodic fade as sufficient on
its own; on this LCD it's belt-and-suspenders anyway). The server computes `asleep` (schedule
or manual) and the display renders on that one signal, flipping within ~5 s of a boundary.
Phase 1 blanks in **software**; dimming the actual **backlight** is a Phase 2 hardware hook.

---

## 14. Branding asset

Matt is producing an **OpenObject mark** and will store it in the project (`~/Code/OpenObject`). Design the **fresh-boot screen** and **idle/empty screen** to consume a logo asset (with a tasteful text fallback if absent), so the mark drops in without layout changes. Aesthetic direction: understated, functional, no clutter.

---

## 15. Repository & distribution

- **Local root:** `~/Code/OpenObject` (already created).
- **GitHub:** Claude Code initializes the repo, structure, and first commit. The repo is **private during development** (2026-06-11) and intended to go **public** later to serve the next-owner mission. Claude drives all git operations; Matt approves pushes at checkpoints (this replaced the original "walk Matt through it step-by-step" plan, see §20).
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

### In-place updates (self-update from GitHub): Phase 1

The player updates itself from this GitHub repo, **from the control panel**, no
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
- **Fast-forward only**, never a force-reset. If the checkout has diverged (local
  edits) the update refuses and says so rather than clobbering it.
- **App-relevant changes only.** A check counts only commits that change what the frame
  runs (`player/`, the served `assets/`, `installer/`). Commits confined to docs, the
  website (`site/`), or repo meta report **up to date** instead of nagging a restart.
- **Runtime data is never touched.** `player/data/` and uploads are gitignored, so a
  pull never disturbs the library, settings, or art.
- **Update channel** (setting): track the **`main`** branch (default) or **tagged
  releases only** (conservative). Releases also carry the prebuilt USB image (above),
  but self-update pulls *source*, not the image.
- **Local-first and offline-safe** (§9): if GitHub is unreachable the check fails
  gracefully and playback is unaffected. Updating is always **owner-initiated**, never
  automatic, never in the playback path.

**Phase split:** Phase 1 builds and tests the whole mechanism on macOS, check,
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

**Built 2026-06-14 (Phase 2, device).** On the frame, **systemd is the supervisor**:
`openobject-player.service` runs `node server.js` directly with `OO_SUPERVISED=1` and
`Restart=always`, and treats the player's exit-75 (self-update + Restart) as a clean relaunch
(`SuccessExitStatus=75`). **No player code changed**, only what relaunches it. The checkout
lives at **`/opt/openobject`** (a real git checkout, `origin` → the GitHub repo) and runtime
data at **`/var/lib/openobject/{data,uploads}`** via `OO_DATA_DIR`/`OO_UPLOADS_DIR`, so a pull
or a re-seed can never touch the library. The player listens on **port 80**
(`CAP_NET_BIND_SERVICE`, still non-root) so the panel is plain `http://openobject.local`.
**Self-update is wired but only goes live when the repo is public**, while private, a
`git fetch` can't authenticate (we set `GIT_TERMINAL_PROMPT=0` so *Check for updates* fails fast
and reports gracefully rather than hanging); making the repo public is the one-step follow-up.
The bench unit is **seeded from a `git bundle`** of the local repo (private repo → no clone
auth needed; full history preserved so self-update works once public).

---

## 16. Documentation requirement (two audiences, kept in lockstep)

Maintain **two** living documents as the build proceeds, not one written once and left to drift:

1. **`docs/HANDOFF.md` (this doc)**, the engineering working doc. Accumulates design tweaks, troubleshooting notes, bench discoveries, and test results.
2. **`docs/SETUP-GUIDE.md`**, the **casual-user** guide. No engineering. For someone who has never seen the handoff and never will.

**Discipline:** whenever a change affects what a new user does, a different BIOS key, an added step, a renamed setting, **update the Setup Guide in the same change.** The Setup Guide must always reflect shipped behavior.

### Setup Guide scaffold (fill placeholders as values are confirmed)

> **What you need before you start**
> - A functioning **Infinite Objects XXL** unit (the 26" square frame) with its **MeLE Quieter 3Q** mini PC on the back.
> - **USB hub:** UGreen USB 3.0 Hub, 4-port, 2 ft (model **25946**).
> - **Left-angle USB-A extension:** CableCreation USB 3.0 Extension, Left Angle, 1 ft (part **CC0516**). _(The **left** angle is the one that fit, it clears the controller's power socket beside the USB port.)_
> - **USB keyboard:** Logitech **K400 Plus** (keyboard + touchpad on one receiver).
> - **USB flash drive:** ≥16 GB (for the installer).
> - **External USB drive:** ≥128 GB (only if preserving the original White Walls backup).
>
> **Steps** (kept in sync with the real procedure)
> 1. Plug the extension into the mini PC's free USB port; attach the hub; attach keyboard + installer drive.
> 2. Power on and enter the BIOS by tapping **`Del`** (the splash hides the prompt, tap from the black screen); set USB boot. _(No "Auto Power On" to enable, the frame already powers on by itself when it has power.)_
> 3. Boot the installer. (Optional: back up the original software first.)
> 4. Install OpenObject; wait for the panel to show the OpenObject screen.
> 5. Join the temporary **OpenObject-Setup** Wi-Fi from your phone; pick your home Wi-Fi; enter the password.
> 6. Open **http://openobject.local** in any browser; drag your art onto the page; set durations and fit/fill; done.

---

## 17. Future enhancements (documented seams, not built in v1)

- **On-chain / NFT source.** The marquee future feature. Reading on-chain art is a **resolution problem, not a display problem**: an NFT is a pointer (contract address + token ID) whose `tokenURI` → metadata → media URL resolves to a file, and that file is a **JPEG/PNG/GIF/MP4/AVIF the v1 display engine already handles**. Intended approach: a **resolver/connector API** (e.g. Alchemy, QuickNode, Reservoir, OpenSea) so the player does *not* run nodes, RPC endpoints, or IPFS gateways itself, connect once, the service returns a media URL, the player downloads it. This slots in as a **third source type** alongside web upload and pull-from-share; everything downstream (sync, library, rotation, pin, fit/fill, loop) is unchanged. **v1 action:** keep the source layer a clean interface so this is a plug-in later, not a teardown. Build none of it now.
- **Web / HTML art pieces (interactive & generative).** *(Working name: "HTML" content, to be
  renamed as we learn the space.)* Some art is not a still or a clip but a **live web page**,
  a generative/interactive `index.html` (often Arweave/IPFS-hosted) that renders on a canvas
  and may expose its own controls. **First target use case:** Bryan Brinkman's *"Azulejo Galo"*
  (an Arweave `index.html` carrying query params for token/wallet/etc.), where clicking the
  piece reveals a **"Toggle Rotation"** control that animates it. Intended UX: the owner
  **pastes a URL**, optionally assigns a **name** and **special functions** (e.g. auto-engage
  "Toggle Rotation"); from then on the piece is a normal library card, Rotation, Pin, duration,
  Fit/Fill behave as usual.
    - **Approach: a curated by-name handler registry, not a generic web automator.** We can't
      drive the infinite ways web content is built and won't try. A small **registry of handlers
      for known/featured collections** maps a recognized collection (or URL pattern) → its
      display name + artist + any **bespoke functions** (hide the page's own UI, programmatically
      engage a control, set a motion query-param, …). Unknown URLs embed as a plain page; only
      recognized collections get white-glove handling, onboarded by **adding a handler, not
      changing the engine**.
    - **Constraints to resolve when built:** a new render kind **`web`** (iframe / Chromium
      webview) alongside still/animated/video; **Fit/Fill is fuzzy** for a page with no intrinsic
      aspect ratio (likely "fill the stage," sized per-collection in the handler); **local-first
      tension (§9)**, a remote URL puts the network in the playback path, so it may need a
      snapshot/cache or be accepted as the one online-dependent kind; **driving the page's own
      controls is cross-origin-blocked** from our page, so automated control (the "Toggle
      Rotation" trigger) most likely rides on the **Chromium kiosk layer (Phase 2)** via script
      injection or known URL params, while the paste-URL/name/functions UX and the `web` library
      row could land in Phase 1; and **trust/security**, remote HTML runs untrusted code on the
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

## 18. Appendix: original White Walls reset (for owners who want to keep it)

Preserved from the vendor's tutorial so a future owner can re-register the **original** Android software *while the vendor's servers still exist*. Not part of OpenObject; offered as a courtesy in the repo.

The original software is a standard Android app running in **Waydroid** (a LineageOS Android 11 container) on **Ubuntu Linux**. To manually reset its account registration (all within the Android container's UI):

1. Connect a USB-A mouse to the mini PC.
2. Reveal the system menu: click-and-drag **downward from the very top** of the screen (this is the Android notification shade; "begin click at top and drag down", it's fiddly).
3. Expand the menu; click the **Settings** cog.
4. **Apps & Notifications** → the **White Walls** app → **Storage & Cache** → **Clear Storage** → **OK** to delete app data.
5. Click the circular **home** button to exit; the unit can re-register as a new White Walls device.

> The full pre-wipe **eMMC image** (§4, step 6) is the more complete preservation: it captures the entire original install, not just a registration reset.

---

## 19. Open items for Matt to confirm/supply

- [x] **Hardware models** (2026-06-13), UGreen 4-port USB 3.0 hub (**25946**); CableCreation **left-angle** USB 3.0 extension (**CC0516**); Logitech **K400 Plus**. Filled into §16 / Setup Guide.
- [x] **Logo / OpenObject mark**, supplied by Matt; optimized marks in `assets/branding/` (source masters in `Logo/`, gitignored). Transparent / white-on-dark variants derived in Phase 1.
- [~] **Bench-verified specs**, **BIOS-entry key `Del`** ✓; **Auto-Power-On = none / firmware auto-on** ✓ (no toggle exists); **CPU N5105** ✓; **UEFI + Secure-Boot-off** ✓; **eMMC = ~128 GB** (116.5 GiB at `/dev/mmcblk0`; corrected 2026-06-13 from the wrong "~256 GB") ✓; **onboard Wi-Fi works under Ubuntu 26.04 live** ✓ (2026-06-13 smoke test). **Wi-Fi module CONFIRMED at the bench (2026-06-14, `lspci -nnk` on installed Debian 13.5 / kernel 6.12.90):** **Intel Jasper Lake PCH CNVi Wi-Fi `[8086:4df0]`**, driver **`iwlwifi`** (this is the FCC TX ID `PD99560D2` part). **Debian's in-box `firmware-iwlwifi` drives it, Wi-Fi joined in the installer, no dongle needed**, closing the §3 Wi-Fi risk. Also captured: iGPU **Intel JasperLake UHD Graphics `[8086:4e61]`** driver **`i915`**; wired NIC **Realtek RTL8111/8168 `[10ec:0123]`** driver **`r8169`**. **Panel resolution CONFIRMED 2026-06-14: 1920×1920** (running framebuffer + native DRM mode; the iGPU also advertises 1920×1080 fallback modes). **Still TBD:** RAM.
- [x] **GitHub repo**, created **private** (2026-06-11); goes public later.
- [x] **Content model confirmed** (2026-06-11), library+select, not replace-on-upload.

---

## 20. Build decision log

Living record of decisions taken during the build (newest first). When any of these affect user-facing behavior, the Setup Guide is updated in the same change (§16).

### 2026-06-16: Tab title separator + real favicon on openobject.io
- **Control-panel tab title** is now "OpenObject · Control Panel". It previously showed "Control" with an em-dash separator; the clearer name plus the middot match the house separator used across the app and the landing page (the em dash also broke the no-em-dash rule for committed text).
- **Landing-page favicon fixed.** openobject.io was shipping a placeholder inline-SVG mark, not the brand. It now uses the real favicon (favicon-32.png) inlined as a base64 data URI, so site/index.html stays one self-contained file (matching how its favicon and OG image were already inlined/linked). It is the same icon already served on openobject.local. Goes live via a gh-pages republish.

### 2026-06-16: Settings tab pass (reorder, password copy, stacked fields, About card, Wi-Fi link color)
A pass over the Settings tab for the next owner: clearer ordering, tighter copy, and consistent link styling. No behavior changes. Order is now Sleep Hours, Software Update, Power, Password, Wi-Fi, About (matches the Setup Guide walkthrough).
- **Password card moved beneath Power.** It's opt-in and off by default, so it now sits below the everyday frame controls instead of above them.
- **Enable button relabeled** from "Turn on password" to "Set password". The New and Confirm fields sit right in the card, so the click saves a value you've already typed (a "Set" action, not a toggle that prompts afterward); it also matches the card's own wording ("set a password") and pairs with the existing "Change password". The red "Turn off password" control is unchanged.
- **Entry fields stacked.** The New and Confirm password inputs were side by side and stretched the full card width, which looked odd; they now stack vertically at a normal field width (capped to match the login box) in both the set and change states.
- **Password copy tightened**, keeping the "open to anyone" preface (its value is the "why" you'd want a password): "The control panel is open to anyone on your network. Optionally set a password. This will not affect the display of art."
- **New About card** at the bottom (after Wi-Fi, the lowest-interaction spot): the OpenObject name and one-line description, a link to the project home (openobject.io) and to the source on GitHub, and a license line ("© 2026 OpenObject · Free for noncommercial use."). The source link is deliberate: it points the next owner of a stranded frame back to the project so they can revive it. Static HTML in control.html.
- **Wi-Fi link color fixed.** The Wi-Fi card's addresses and the openobject.local link were falling back to the browser's default blue: a refactor had moved the card to inline paragraphs and left the old `.reach-list` link CSS unmatched. Gave them the house near-white + underline treatment (matching the About links) and removed the five dead `.reach-list` rules that caused the gap.
- **Settings stays single-column.** A two-column / half-width layout was considered and declined: the panel is mostly phone-driven (columns collapse on a narrow screen anyway) and the two tallest cards (Sleep Hours, Password) already use the full width, so halving them would just wrap their controls. If Settings grows, the cleaner lever is grouping, not columns.

### 2026-06-16: Security follow-ups (filename XSS, CSP, upload/disk guards, path scrub)
A read-only security review (private home-network deployment) found no committed secrets; the items it flagged were fixed this session.
- **Stored XSS fixed.** The control panel rendered an uploaded filename (`original_name`, attacker-controlled) into `innerHTML` unescaped. Added an `esc()` helper, used for `original_name` in the Library and Rotation views. Verified in-browser: a `"><img onerror=...>` filename now renders as literal text, no script runs.
- **Content-Security-Policy added** (defense in depth): a strict header (`script-src 'self'`, no inline, etc.). All scripts and styles are external same-origin files, so it broke nothing; the control panel and display both load clean.
- **Upload + disk guards (§8).** Per-file size cap (`OO_MAX_UPLOAD_MB`, default 512 MB) and a per-request file count (`OO_MAX_UPLOAD_FILES`, default 50); an oversize file is refused (HTTP 413) with no orphan left on disk. A pre-flight free-space check (`OO_MIN_FREE_MB`, default 2048 MB) refuses uploads (HTTP 507) before the eMMC can fill and wedge the frame. The control panel surfaces the server's message on a failed upload.
- **Privacy.** Scrubbed the local macOS home path from this doc (now `~/Code/OpenObject`); future commits use a GitHub noreply email (past commits keep the old address).
- **Optional control-panel password (built, §12).** Was deferred; now implemented, still OFF by default so an open frame is unchanged. When the owner sets a password in Settings, the control panel and every mutating API require a session (login overlay); the kiosk surface (`/display`, `/api/display`, `/healthz`, `/assets`, `/uploads`) stays open so the display never needs a credential. Stateless HMAC-signed httpOnly cookie, scrypt-hashed password in the settings table, no new dependency. Verified in-browser: off, turn on, logout, wrong password, login, and the kiosk reachable while locked. Folded in a small cleanup: control.js now reuses the existing escapeHtml helper instead of a duplicate.

### 2026-06-15: Reboot / Shut down made real on the frame (§17 closed)
The Reboot and Shut down buttons were inert stubs; they now actually reboot / power off the installed frame, closing the §17 "real device power-off and reboot" item.
- **server.js:** Reboot runs `systemctl reboot`, Shut down runs `systemctl poweroff`, but only on the Linux device (`process.platform`); off-device (the dev Mac) both stay inert stubs, so a dev machine is never powered off. A missing grant is reported rather than failing silently, and the panel treats a dropped connection as the frame going down (polling it back after a reboot).
- **installer/install.sh:** installs polkit and writes a scoped polkit rule letting the `openobject` user run those two actions without a password (the `-multiple-sessions` variants included, since the kiosk session is always active).
- **Existing frames** (provisioned before this) apply the grant once: self-update, then re-run `sudo bash /opt/openobject/installer/install.sh`. New installs get it automatically. The real path was written on macOS (where it verifies as a safe stub) and confirmed on the frame.

### 2026-06-15: Control panel polish: doc-only updates no longer nag, plus a Reboot button
Two next-owner UX fixes the landing-page work surfaced:
- **Update check is now path-aware.** `check()` reads the files an incoming fast-forward would change and reports an update only when something the frame actually runs is among them (`player/`, the served `assets/`, `installer/`). Commits confined to `docs/`, the website (`site/`), or repo meta now report "up to date" instead of prompting a pointless Update & Restart. Denylist-based, so unknown or new paths still count as a real update (a genuine update is never hidden). Verified against the real `a134b72..HEAD` range (all docs/site) reading as up to date.
- **Reboot button added** to the Power controls, between Restart and Shut down. Like Shut down it is an inert stub for now; the real `systemctl reboot` / `poweroff` wiring stays the §17 task (one polkit grant in `install.sh` away).

### 2026-06-15: openobject.io landing page live
A public landing page now lives at **https://openobject.io** (and `www.` redirects to the apex), served by GitHub Pages with an enforced HTTPS certificate.
- **Source:** a single self-contained `site/index.html` on `main` (dark wiki-style page, inline CSS, the logo recolored white, Open Graph and Twitter card tags, a "Find us on X" footer), with friendly copy drawn from the README and Setup Guide voice.
- **Hosting:** an orphan `gh-pages` branch holding exactly `index.html` plus a `CNAME` file (`openobject.io`); the Pages source is that branch at its root. To update the live page later, edit `site/index.html` and re-publish to gh-pages keeping both files (dropping the CNAME would disconnect the domain).
- **DNS (GoDaddy):** apex A and AAAA records pointing at the GitHub Pages addresses, a `www` CNAME to `mattonchain.github.io`, and a domain-verification TXT (verified at the account level for takeover protection).

### 2026-06-15: Kiosk cursor hidden, console access, opt-in SSH
All delivered over the air (self-update + a power-cycle, no re-imaging), which exercised the Tier-1 update path end to end.
- **Cursor solved.** cage takes its pointer from the cursor theme literally named `default` and ignores `XCURSOR_THEME`, so the earlier blank-theme attempt was a no-op even though cage had the variable. `start-kiosk.sh` now exposes the shipped transparent `blank` theme under the name `default` (a symlink rebuilt on each start, so it self-heals and fresh installs get it). Verified gone on the frame; the matching §17 enhancement item is removed.
- **Console access (`cage -s`).** cage locks the VT unless launched with `-s`; added it, so `Ctrl+Alt+F2` reaches a Debian text console for servicing. On the bench K400 the top-row keys are media keys, so in practice it is `Ctrl+Alt+Fn+F2` (`Ctrl+Alt+F1` returns to the art; from the shell, `sudo chvt 1` / `chvt 2` switch reliably if the function keys fight you). git against `/opt/openobject` must run as the owning service user (`sudo -u openobject git ...`) or git refuses with "dubious ownership."
- **SSH: installed but OFF by default.** `install.sh` now installs `openssh-server` and disables it, so a shipped frame opens no port until its owner runs `sudo systemctl enable --now ssh` (Matt's call, for everyone). Frames provisioned before this need a one-time `sudo apt install openssh-server` first, since their installer already ran.
- **Lockfile heads-up, fixed:** the "local file changes are present" line on the Software Update card was only `player/package-lock.json`, which `npm install` rewrote at provisioning. Fixed by switching the installer and the updater to **`npm ci`** (commit `f3e209b`), which installs exactly what the lockfile pins and never rewrites it (committed lockfile verified in sync, no devDependencies). An already-provisioned frame clears its existing copy once with `sudo -u openobject git -C /opt/openobject checkout -- player/package-lock.json`. (Matt, 2026-06-15.)

### 2026-06-14: Public launch, self-update verified on the real frame, public-facing copy pass
The repo went **public** under the **PolyForm Noncommercial License 1.0.0** (source available for noncommercial use), and over-the-air self-update was **verified end to end on the actual frame**: from the control panel the frame fetched the now-public repo, fast-forwarded `5b69400` to `da15978` (nine commits), reinstalled dependencies, and restarted the player, with the commit on the Software Update card flipping to confirm it. The version stays `0.1.0` and the date stays today because every commit landed in one day, so the **commit hash is the precise "it updated" indicator**, which is exactly what that field exists for.
- **Public-facing copy pass:** README and SETUP-GUIDE rewritten in a casual, human voice. The original decay is described generically, with the **White Walls app credited as the stranded hero** (the cloud services it relied on going away was not its fault). Added a **No warranty** section and an **Independence / not-affiliated** notice. SETUP-GUIDE gained a frank "So you want to try this?" preface, and its install steps now point to the real `installer/` runbook instead of promising the unbuilt one-tap image and setup-AP Wi-Fi.
- **Em dashes removed from all repo copy** (README, SETUP-GUIDE, HANDOFF, both appendixes, the installer runbook, INSTALL-NOTES, CLAUDE.md, the player README): Matt considers heavy em-dash use an AI tell. Headers take a colon, body text a comma. `LICENSE` left verbatim; code comments left for now.
- **Attempted to hide the kiosk cursor** (`cursor: none` on `/display`) so the setup keyboard's receiver can stay attached for local access. On the first booted frame it does NOT take effect: the CSS loads (the sleep-mark dim from the same file applies) but cage still draws a pointer on the art. Logged in §17 for a proper compositor-level fix.
- **Logged in §17:** wire a real device power-off and a true device reboot, since the bench self-update exposed Shut down as a still-inert stub on the real frame. (Matt, 2026-06-14.)

### 2026-06-14: License chosen + repo prepped to go public (source available, noncommercial)
- **License = PolyForm Noncommercial License 1.0.0** (Matt's call): the source is **available for
  noncommercial use**, anyone may use, modify, and share OpenObject to revive and run their *own*
  frame (personal/hobby), but **may not** sell it, charge for it, or build it into a product or other
  commercial/revenue venture. Deliberately **not** "open source" (the noncommercial limit), call it
  *"source available, noncommercial"* everywhere. **Copyright holder = The Museum of Digital Art
  (@mymoda_io)** (Matt's established X handle/brand).
- Added a root `LICENSE` (verbatim official PolyForm text + a `Required Notice:` copyright line);
  set `player/package.json` `license` → `PolyForm-Noncommercial-1.0.0` + `author` (kept
  `"private": true`, that only blocks an accidental npm publish, unrelated to GitHub visibility).
- **README refreshed for a public front page** and corrected stale facts: CPU **N5100 → N5105**,
  added **WebM**, dropped the removed **Random** order (Sequence/Shuffle only), status now "working
  on real hardware," `installer/` described, added a Get-started section + the 1920×1920 panel spec.
- **The visibility flip itself is Matt's manual step** (GitHub → Settings → Change visibility →
  Public); the repo *content* is ready. Once public, the frame's self-update can finally pull
  (resolves the repo-public/license trigger). (Matt, 2026-06-14.)

### 2026-06-14: Phase 2B VERIFIED on hardware: the frame runs OpenObject
Bench bring-up of the installer succeeded **end-to-end on the real MeLE frame, first run.**
- Flashed Debian 13.5 netinst (balenaEtcher) → wiped the eMMC → minimal Debian (no desktop) →
  `installer/install.sh` provisioned Node 22, Chromium + cage, Avahi, NetworkManager, the systemd
  units, and **passed its self-test** (`/healthz` on :80). After `reboot` the panel came up
  **edge-to-edge on `/display`** (cage + Chromium kiosk) with the branded idle screen, the single
  riskiest piece, working on the first boot.
- **Verified:** `http://openobject.local` reachable from a phone over Wi-Fi; uploads work
  (incl. a **285 MB video** looping); rotation cycles; the cursor is gone once the setup keyboard's
  USB receiver is unplugged (the wall-mounted state, so no `cursor: none` code was needed).
- **Hardware confirmed (`lspci`):** Wi-Fi **Intel Jasper Lake CNVi `[8086:4df0]` / `iwlwifi`**
  (Debian in-box firmware, no dongle), iGPU **`[8086:4e61]` / i915**, NIC **Realtek / r8169**,
  panel **1920×1920** square. Filled the §19 Wi-Fi placeholder + the §2 table.
- **NM Wi-Fi handoff** no-ops on this ifupdown-managed install (skipped, non-fatal, by design);
  Wi-Fi + Avahi work regardless. Full NM ownership stays with the later setup-AP milestone.
- **Polish from the bench test:** video Library cards now show a first-frame poster (`#t=0.1`
  media fragment, no transcode); the blank/sleep mark dimmed **0.2 → 0.1** (Matt).
- **Deployment note:** code fixes reach the installed frame only via self-update (needs the repo
  public) or a re-seed, the first concrete case of the repo-public/license trigger. Running bench
  log: `installer/INSTALL-NOTES.md`. (Matt, 2026-06-14.)

### 2026-06-14: Phase 2B: UEFI Debian + Chromium-kiosk installer built (Mac side)
Built the installer that turns a minimal Debian into an OpenObject appliance; bench test pending.
- **OS + kiosk locked (§3):** minimal **Debian stable** (UEFI, no desktop) via the standard
  netinst, then an idempotent **`installer/install.sh`** provisions on top. Display surface =
  **`cage`** (Wayland kiosk compositor) running **Chromium `--kiosk`** at `localhost/display`,
  no X / WM / DM. X11 + Openbox documented as the fallback.
- **systemd replaces `supervisor.js` (§15)** with **no player code change**, the player already
  honored `OO_SUPERVISED` + exit-75 and `PORT`/`OO_DATA_DIR`/`OO_UPLOADS_DIR`, so Phase 2 is pure
  *configuration*. `openobject-player.service` (`Restart=always`, `SuccessExitStatus=75`,
  `CAP_NET_BIND_SERVICE` → **port 80**) + `openobject-kiosk.service` (cage on tty1 via the
  logind-seat `PAMName=login` pattern).
- **Layout:** code at `/opt/openobject` (git checkout, `origin` → GitHub), runtime data at
  `/var/lib/openobject/` (outside the checkout, so self-update/re-seed can't touch the library).
- **Private-repo seeding:** the bench unit is seeded from a **`git bundle`** of the local repo
  (no clone-auth needed, history preserved). **Self-update is wired but goes live only when the
  repo is public** (`GIT_TERMINAL_PROMPT=0` makes the private-repo fetch fail fast/graceful).
- **NetworkManager** becomes the network manager (foundation for the §11 setup-AP); the handoff
  from the netinst's Wi-Fi runs **last** and is **non-fatal** (proves itself before retiring the
  old config, else leaves the working Wi-Fi alone).
- **Mac-side verification (no hardware):** `bash -n` on all scripts ✓; a **`git bundle`
  round-trip** ✓, clones to a clean committed-only checkout (no `node_modules`/`data`/`uploads`,
  §8) and `npm install` resolves. Files: `installer/install.sh`, `installer/systemd/*.service`,
  `installer/kiosk/{start-kiosk,chromium-kiosk}.sh`, `installer/README.md`. **Out of scope this
  session:** the §11 setup-AP/captive portal and the §15 one-file release image. (Matt, 2026-06-14.)

### 2026-06-13: Phase 2 bench: live boot, Wi-Fi confirmed, factory eMMC cloned
Second hands-on bench session, booted our own Linux on the unit and made the pre-wipe backup.
- **Live USB:** flashed **Ubuntu 26.04 LTS desktop** (current LTS, newest kernel/firmware) to a USB stick from the Mac (`dd`), booted the MeLE via **Save & Exit → Boot Override → `UEFI: <stick>`** (the factory `ubuntu (eMMC A3V012)` entry is the eMMC; `Del` → BIOS as expected), chose **Try Ubuntu** (live; no install).
- **Wi-Fi smoke test PASSED:** the onboard Wi-Fi scanned, associated, and carried traffic under Ubuntu 26.04, the single biggest Phase-2 unknown, now de-risked (Wi-Fi-only install is viable, §11). Exact chip/driver name still to capture (`lspci -nnk`).
- **eMMC size corrected, ~128 GB, not 256 GB.** Linux `lsblk` shows **`/dev/mmcblk0` = 116.5 GiB** (EFI `p1` 512 MB + ext4 `p2` 116 GB factory Ubuntu root, + 4 MB `mmcblk0boot0/1`). The earlier "~256 GB" came from the Android storage screen and was wrong; `lsblk` is authoritative, so the original "128 GB" was right. **§2 / §4 / §19 corrected**, and the Linux path `/dev/mmcblk0` resolves a §19 TBD.
- **Factory eMMC cloned (capture-only backup):** mounted a 2 TB exFAT USB drive in the live session and ran `ddrescue /dev/mmcblk0 → xxl-emmc.img` (read-only on the eMMC; ~117 GB image). Distilled into a new **optional** appendix, `docs/appendix-backup-original.md` (bold "already unusable / no supported way back / capture-only" disclaimer, per the install-doc strategy). SETUP-GUIDE parts list + the White Walls appendix updated in lockstep; the White Walls appendix's "Android-x86" line corrected to Waydroid-on-Ubuntu.
- **Bench-process note:** SSH from the Mac to the live unit could not be established (Mac is multi-homed Ethernet + Wi-Fi, and Mac→unit stayed unreachable even Wi-Fi-only, a deeper Mac-side routing/policy issue; the unit could reach the Mac fine). Worked around by hand-typing commands at the frame and reading the screen via phone photos. SSH is a build-time convenience only and never appears in the next-owner flow. (Matt, 2026-06-13.)

### 2026-06-13: Hardware bench identification (Phase 2 kickoff)
First hands-on session with the actual XXL unit (original OS reachable). Identity **confirmed**; several prior assumptions **corrected**:
- **CPU = Intel Celeron N5105** (Jasper Lake / "JasperLake ULX"), 2.00 GHz, **§2 corrected from the wrong "N5100."** BIOS board name is **`XXL`** (IO custom badge; same N5105 platform as the MeLE Quieter 3Q label).
- **Original OS is Ubuntu + Waydroid, not "Android-x86."** Host = **Ubuntu Linux**; "White Walls" runs as an **Android app inside Waydroid** (a **LineageOS Android 11** container, `lineage_waydroid_x86_64`, `RQ3A.211001.001`). The Android-looking UI is the container. **§2, §4, §18 corrected.** (§18's notification-shade / Settings→Apps reset steps still apply, that's the container's UI.)
- **Firmware:** AMI Aptio `ML_JPL1 V1.0.0 x64` (core 2.22.1282, 12/2023). **`Del`** enters Setup (Quiet Boot hides the prompt, tap from the black screen). **No BIOS password** (Administrator access). **Secure Boot off.** **UEFI.** Boot entry `ubuntu (eMMC A3V012)`. → the **UEFI USB installer** path is clear, no signing/Secure-Boot hurdle.
- **Storage = ~256 GB eMMC** (id `A3V012`), **§2 corrected from "128 GB."**
- **Auto-Power-On: no BIOS toggle exists** (checked `PCH-IO Configuration`; no "State After G3" / "Restore AC Power Loss"). Auto-on is the firmware default, matches the confirmed replug-boot (§10). The §19 "Auto-Power-On label" item resolves to *there isn't one*. **§4, §10, §19 updated.**
- **Access kit / BOM confirmed:** UGreen 4-port USB 3.0 hub (**25946**); CableCreation **left-angle** USB 3.0 extension (**CC0516**), the **left** angle clears the controller's power socket beside the USB port; Logitech **K400 Plus**. Insert trick: slide the MeLE up to free the HDMI/USB-C, seat the extender, reseat, slide back down. **§4, §16, §19 + Setup Guide updated** ("right-angle" → "left-angle").
- **Reference:** factory stack boots slowly (~1 min to art) → our native Node + Chromium-kiosk should beat it easily; Ubuntu already drives the N5105 iGPU + square panel + Wi-Fi, so **Debian** is low-risk (§3).
- **Still TBD:** Wi-Fi module/driver under Linux (FCC TX ID `PD99560D2`), RAM, exact eMMC Linux path/free space, all gettable once our OS boots.

### 2026-06-13: Shut down / Restart countdown-cancel; power-cycle boots confirmed
- **Power actions now arm a countdown the owner can cancel** (Matt): **Shut down** counts down
  **10s**, **Restart** **5s**, shown inline in the Power card with a **Cancel** button (replacing the
  native confirm dialogs). At zero the action fires; Cancel aborts and re-enables the buttons, a
  safety net against a misclick on a hard-to-undo action.
- **Confirmed (Matt): the unit boots when power is unplugged and restored**, so cycling the outlet
  is a reliable boot, the hard-to-reach physical power button is a non-issue, and after a Shut down
  you power back on by replugging (or a smart plug). Recorded in §10; the exact Auto-Power-On
  default/label is still bench-TBD (§19). (Matt, 2026-06-13.)

### 2026-06-13: Terminology nailed down; control-panel copy pass; onboarding reference
- **Canonical vocabulary (user-facing):** **frame** = the physical device; **control panel** = the web
  UI you control it from; **screen** = the display surface; **display** = the `/display` kiosk page only.
  Swept the control panel + Setup Guide to match, e.g. header **"Blank panel" → "Blank screen"**, restart/
  update status copy now says "frame" (the device) not "panel," and "Reach this panel" → "Reach the control
  panel." (Engineering prose in this doc still says "panel" for the physical LCD where that's the precise
  hardware term, the scheme governs user-facing copy.)
- **Power-card copy tightened** (Matt): Restart note → **"Restarts the frame."** (dropped "and brings it
  right back", restart already implies the return); Shut down note → **"Turns off the frame."** Button
  stays **"Shut down"** (two words, it's the verb, matching macOS/Windows).
- **Wi-Fi card:** removed "no keyboard needed" (don't tell users what they don't need); "frame" throughout.
- **Onboarding reference recorded (§11):** Matt shared the stock Infinite Objects Wi-Fi flow; logged it
  plus our refinements (QR codes on the setup screen, plain labels, pick-from-scanned-list, two-screen
  confirmation, recovery/self-heal, AP naming) as the Phase-2 design. Build none now. (Matt, 2026-06-13.)

### 2026-06-13: Hardware stubs (Restart / Shut down / Wi-Fi); Phase 1 feature-complete
- **Settings → Power card:** **Restart** ships **live**, an app-level soft-restart through the
  supervisor (exit → relaunch, the §15 path), so it genuinely works browser-only with no hardware
  and is identical to what systemd will run on the device. **Shut down** is a visible-but-inert
  **stub** (can't/mustn't power off the dev Mac); Phase 2 wires a real OS power-off. Restart was
  made live rather than a stub (Matt's call) because the supervisor already made it durable and
  free, the old "inert stub" note predated the supervisor.
- **Settings → Wi-Fi card:** an explanatory **stub** for the first-run OpenObject-Setup AP +
  captive-page flow (§11; Phase 2), plus a **real** "reach this panel" helper showing the live LAN
  address(es) and the `openobject.local` name.
- **Backend:** `GET /api/system` (supervised flag, port, mDNS name, LAN addresses),
  `POST /api/system/restart` (live under the supervisor; reports `needsManualRestart` under
  start:direct), `POST /api/system/shutdown` (inert stub + message). `/healthz` gained a per-process
  **`boot`** id so the panel can confirm a plain restart, unchanged version, actually bounced. All
  owner-initiated, none in the playback path.
- **Phase-2 power note recorded:** a full **device reboot** (`systemctl reboot`) and real
  **power-off** (`systemctl poweroff`) are easy on the Linux device; with BIOS Auto-Power-On a
  power-off returns on next power, so a true "off" is the outlet/smart plug (§10).
- **Phase 1 is now feature-complete on macOS**, server, library/upload, control panel, display +
  behaviors, progressive sync, sleep hours, self-update, and these stubs. Remaining work is
  hardware/Phase 2. (Matt, 2026-06-13.)

### 2026-06-13: Self-update UI redesign + control-panel layout
- **Software Update card decluttered to the traditional shape** (Matt's review): a clear
  **Current version** line, `version · date · commit` (e.g. `0.1.0 · June 13, 2026 · a1b2c3d`,
  the commit a small unlabeled link to GitHub), then **Check for updates**, and on an available
  update a plain-English recap of what's in it, a **What's new ↗** link to the GitHub diff, and
  **Update & Restart** / **Not now**. The version number alone doesn't change every update, so the
  **build date** is the human "it updated" signal and the short **commit** the precise one (covers
  two-updates-in-a-day); the jargon (`commit`, `tracking main`, raw hashes in the body) is gone.
  New backend fields feed it: commit `date` (`git %cs`) and `repoUrl`/`compareUrl` derived from the
  origin remote (suppressed for non-web remotes).
- **Update channel toggle removed from the UI**, track the latest on `main` only. The channel
  machinery stays in the backend (`update_channel`, `PUT /api/update/channel`), so a plain "vetted
  releases" choice can return if/when we publish tagged releases (pairs with going public).
  "Stable releases" was dropped from the UI because we have none yet, it would only read "no
  releases yet."
- **Section headers Title-Cased** (Sleep Hours, Software Update) via a shared `.section-title`.
- **Control-panel layout: tabs moved to the top; the upload dropzone now lives inside the Library
  tab** (no longer pinned above all tabs). Uploading is a Library action, so seeing it from
  Rotation/Settings was odd. **This reverses the earlier "upload pinned above the tabs" call** (see
  the Rotation-curation entry below). A "drop a file anywhere → Library" convenience was considered
  and declined, keep it simple. (Matt, 2026-06-13.)

### 2026-06-13: Self-update from GitHub built (§15)
- **Self-update shipped, browser-driven end to end (§15).** The **Settings** tab gains a
  **Software update** card: it shows the running version + commit + tracked branch, a **Check
  for updates** button (git fetch + compare to the channel's target), and, when a newer,
  fast-forwardable version exists, an **Update & restart** button that pulls
  (`git merge --ff-only`), reinstalls dependencies **only if the manifest changed**, and
  relaunches. `/healthz` now also reports the running **commit**, which the panel polls to
  confirm the new version came back up. Everything happens over the browser, **no hardware
  access**, which is the whole point of building it now.
- **Restart mechanism = a tiny supervisor (`player/supervisor.js`).** `npm start` now runs the
  supervisor; it spawns `node server.js` and relaunches it when the player exits with restart
  code **75** after an update. `npm run start:direct` runs the server alone (no auto-relaunch,
  self-update then asks for a manual restart). This is the Phase-1 stand-in for the device's
  service manager; **Phase 2 swaps it for a systemd unit** (`Restart=always`), the player side
  unchanged. The launch config now points at the supervisor.
- **Guardrails (all verified):** **fast-forward only**, a diverged checkout (local commits)
  refuses with a clear message and changes nothing, never a force-reset; **runtime data
  untouched**, `player/data/` + uploads are gitignored, invisible to the pull; **offline-safe**
, a failed fetch reports gracefully and never touches playback; **owner-initiated only**,
  never automatic, never in the playback path. Art still never touches the repo (§8).
- **Channel setting** (`update_channel`): track **`main`** (default) or **tagged releases**
  only (§12). New routes: `GET /api/update` (instant, no-network status), `POST /api/update/check`,
  `POST /api/update/apply`, `PUT /api/update/channel`.
- **Tested end-to-end on macOS without real upstream commits** via a throwaway bare-clone
  "fake origin" sandbox (snapshot the working tree → bare repo → work checkout → push synthetic
  commits): proved no-update → update → fast-forward + restart (`/healthz` commit flips) →
  divergence refusal, plus the offline and not-a-git-checkout paths. The sandbox is disposable
  and never touches the real repo or GitHub. (Matt, 2026-06-13.)

### 2026-06-13: Sleep hours built (+ manual Blank)
- **Sleep hours shipped (§13):** up to **two daily blank windows**, each with an **enable
  checkbox** (work + night); times on a **12-hour clock with an AM/PM** segmented toggle,
  wrap-past-midnight supported with an auto **"overnight"** tag. Off by default.
- **Manual "Blank panel"** toggle added to the header, art off on demand, independent of the
  schedule (the parked Blank/Pause companion; it lives in the header we said we'd revisit).
- **Sleep screen** mirrors the boot/idle mark exactly, same size/placement, **dimmed, no
  caption**, with a slow **pixel-shift** (~90 s) for burn-in insurance. Pixel-shift was chosen
  over a periodic fade (the standard technique, sufficient on its own; Matt's call). Playback
  stops while asleep and resumes on wake.
- **Server-computed `asleep`** (from settings `sleep_ranges` + `manual_blank`) is returned in
  `/api/display`; `PUT /api/settings` gained validated `sleepRanges` + `manualBlank`. No DB
  change, both are key/value settings. Phase 1 blanks in software; backlight dimming is a
  Phase 2 hook. (Matt, 2026-06-13.)
- **Control panel reorganized to three tabs, Library · Rotation · Settings.** Sleep hours
  moved into the new **Settings** tab (its future home for self-update, restart/shutdown,
  Wi-Fi onboarding); the **duration/order** bar moved into the **Rotation** tab (it governs how
  the rotation cycles). The top of the page is now just upload + tabs. Sleep mark dimmed from
  0.3 to **~0.2**. (Matt, 2026-06-13.)

### 2026-06-13: Logged: Web/HTML art pieces (future seam, §17)
- **Logged a future enhancement, a "HTML" content type** (working name): add a **live web
  page** (generative/interactive `index.html`, e.g. Arweave-hosted) as a piece via
  **paste-URL + optional name + special functions**, handled through a **curated by-name
  registry for featured collections** (first target: Bryan Brinkman's *"Azulejo Galo"* and
  its in-page "Toggle Rotation" control). It's a new render kind (`web`, iframe/webview) and a
  §8 source-layer seam, distinct from the on-chain/NFT seam (which resolves to a media file).
  **Not built**; captured in §17 with its constraints (Fit/Fill semantics, §9 local-first
  tension, cross-origin control → likely Phase-2 kiosk, sandboxing). (Matt, 2026-06-13.)

### 2026-06-13: Rotation curation (membership + manual order); settings bar redesign
- **The Rotation is now a curated subset, not the whole Library**, completes the §7
  Library/Rotation/Pin model. Two new `library` columns, `in_rotation` (default 1) and
  `position`, added by an **idempotent PRAGMA-guarded migration** that backfills existing
  rows to in-rotation in upload order, so prior behavior is unchanged. New uploads
  **auto-join** at the end of the order, keeps the zero-effort "everything I upload plays"
  default; unwanted pieces are removed in the Rotation tab. (Matt, 2026-06-13.)
- **API:** `PATCH /api/library/:id` now also accepts `inRotation`; added `GET /api/rotation`
  (curated members in order, *not* pin-collapsed, that's display-only) and
  `PUT /api/rotation/order { order:[id,…] }` (renumbers members 0..n-1 in one transaction).
- **Pin now overrides Rotation membership** (§7 "overriding the cycle"): `/api/display`
  resolves the pinned piece from the **full Library** and collapses to it even if it isn't
  in the Rotation, fixes the case where a pinned non-member would vanish once
  Rotation ≠ Library. `display.js` is unchanged (its own collapse became a harmless no-op).
- **Control panel reorganized into two tabs, Library and Rotation** (Matt's "separate page
  you toggle to, then back" call, over reordering inside the Library grid). Library tab:
  each card gains a corner **add/remove-from-rotation** toggle. Rotation tab: the ordered
  list, reorderable by **drag *and* ↑/↓ arrows** (arrows are the touch-safe path on
  iPhone/iPad, where native drag is unreliable), **✕** to remove; a hint notes the order
  drives Sequence and is cosmetic under Shuffle. Rotation-list thumbnails **honor each
  clip's Fit/Fill** so they match the Library cards and the panel. Control icons (grip,
  arrows, remove) are **inline SVG, no webfont**, so the panel works on an offline frame.
  Upload + settings stay persistent above the tabs.
- **Settings bar redesigned (Option A of three mockups):** a −/+ **stepper** on the
  duration, **segmented** unit (sec/min/hr) and **segmented** order (Sequence/Shuffle)
  replacing the dropdowns. (Matt picked Option A, 2026-06-13.)
- **Sleep-screen direction captured for §13** (design intent; Sleep Hours not built yet).

### 2026-06-12: Display rotation engine; global equal-time duration
- **Duration is one global, equal-time setting for every piece**, no per-clip duration
  (revises §7/§12). Stills hold for it; animated + video loop to fill it; a clip longer
  than the duration is cut when the timer advances; video always loops. Dropped the
  per-clip `duration_ms`/`video_full` columns from the `library` table. (Matt, 2026-06-12.)
- **/display rotation engine built** (§6, §7, §9): renders the Rotation (v1 = the whole
  Library, upload order) edge-to-edge with per-clip Fit/Fill, crossfades between pieces,
  Sequence/Shuffle, always muted. New uploads/deletes, Fit/Fill flips, and
  duration/order changes fold in live via a ~5s poll, no loop restart (§9 progressive).
- **Control panel** gains a global Settings bar (duration + order) and a per-clip
  Fit/Fill toggle. New endpoints: `GET/PUT /api/settings`, `GET /api/display`,
  `PATCH /api/library/:id {fit}`.
- **Pin** (hold one piece permanently, collapses the rotation to it, resumes on unpin)
  and **duration units** (seconds / minutes / hours) included. New endpoints
  `PUT /api/pin/:id` + `DELETE /api/pin`; deleting a pinned piece clears the pin.
- **Rotation default = the whole Library**; new uploads auto-join. Curation
  (remove-from-rotation, reorder) comes next. (Matt, 2026-06-12.)
- **Web-app favicon + apple-touch-icon** added (white-bg logo at 16/32/180 px), the
  apple-touch-icon gives a proper home-screen icon for phone/iPad control.
- **Random rotation order removed**, Shuffle already gives random order with no
  near-term repeats; pure Random (independent pick, can repeat back-to-back) was an odd
  fit for an art frame. Modes are now **Sequence / Shuffle** only. (Matt, 2026-06-12.)

### 2026-06-12: Upload + Library shipped; node:sqlite locked
- **SQLite library chosen: Node's built-in `node:sqlite`** (over better-sqlite3), zero
  native deps, no build step, best for revivability; all DB access is contained in
  `player/src/db.js`, so a later swap stays local. Its lone startup ExperimentalWarning is
  silenced surgically (only that one line; every other Node warning still prints). (Matt's
  call, 2026-06-12.)
- **Web upload + Library built** (§7, §8): drag/tap multi-upload via `multer` (pure-JS,
  no native build), stored **byte-for-byte** under `player/uploads/`; a format gate by
  extension accepts JPEG/PNG/GIF/AVIF/WebP/MP4/MOV/WebM and **skips the rest silently** (§6).
  Adds a `library` table + `GET/POST/DELETE /api/library` (delete removes the row *and*
  the file).
- **WebM added to the v1 video formats** (after MOV): open, royalty-free VP8/VP9/AV1,
  always compiled into Chromium, so it's the most reliably-playable video on a minimal
  Linux frame (H.264/MP4 may need a codec package there). Same `kind: video` loop path,
  so trivial to add. List order also set to AVIF before WebP. (Matt, 2026-06-12.)
- **`/` is now the control panel** (was a redirect to `/display`); the kiosk stage stays
  at `/display`. The display still renders only the Rotation, uploads fill the Library;
  the rotation engine that puts them on the panel is the next checkpoint.

### 2026-06-12: Self-update from GitHub (Phase 1)
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

### 2026-06-12: Bench caution: screws above the MeLE
- **Do not remove the two screws on the bracket above the MeLE** when working at the
  back of the XXL, they retain captive nuts inside the chassis that fall in if the
  screws are backed out, forcing a near-full teardown to recover. Documented in §4 and
  the Setup Guide. (Bench lesson from Matt.)

### 2026-06-11: Branding asset approach
- **Idle/boot-screen logo variants will be produced with Potrace → SVG**
  (`openobject-logo.svg`): single-color and transparent so CSS recolors it
  white-on-dark or black-on-light; transparent PNG exports derived from it as needed.
  Trace source: the **2k master** (`Logo/logo-2k.png`), falling back to `logo_orig.png`
  if the higher-res export proves a soft upscale rather than added detail, the 2k/4k
  files are near-uncompressed, so verify edge crispness at trace time. The committed
  PNG marks (≤1024) stay sourced from the clean `logo_orig.png`.
  A plain raster color-inverse was rejected (trivial, Matt does that in Photoshop if
  ever needed). **SVG here is a UI/brand asset only**; displayed user *art* in SVG
  stays deferred per §6. (§14)
- **Logo source re-centered** by Matt (subtle but critical glyph centering fix); the
  committed marks were refreshed from the new source (commit `df57ec6`).

### 2026-06-11: Phase 0 kickoff
- **Content model confirmed:** Library + select, persistent library, curated rotation, pin one clip. Not replace-on-upload. (§7)
- **Stack chosen:** Node.js + Express + vanilla HTML/CSS/JS + SQLite, no build step, one language across server and the browser display page, chosen for revivability. (§5)
- **Display is edge-to-edge with zero chrome:** full-panel black stage, no decorative frame/border/padding, media to the physical edges. (§6)
- **Default render mode is Fit** (original aspect ratio); per-clip Fill override retained. An earlier "Fill by default" idea was rejected. (§6, §12)
- **Rotation order gains Random** alongside Sequence and Shuffle, three modes, defined in §7.
- **Repo is private for now,** intended to go public later; the next-owner mission still drives design. (§15)
- **Logo supplied** by Matt; optimized marks committed under `assets/branding/`, large masters kept out of git. (§14, §19)
- **Workflow:** Claude drives all git/gh; commits + pushes happen at checkpoints on Matt's approval; outward-facing actions gated. No hardware access yet, Linux/kiosk/installer is Phase 2.

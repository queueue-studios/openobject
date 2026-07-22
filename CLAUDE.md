# CLAUDE.md: OpenObject working rules

Orientation for any Claude (or human) working in this repo. The authoritative
spec is **`docs/HANDOFF.md`** (engineering), mirrored for non-technical owners by
**`docs/SETUP-GUIDE.md`**. Read HANDOFF before non-trivial work.

## What this is
OpenObject is self-hosted replacement software for the **Infinite Objects XXL**
26" square (1:1) digital art frame. It wipes the frame's **MeLE Quieter 3Q** mini
PC and turns it into a clean local art player: shows local images/videos,
controlled from a web page, depends on no external service. Mission: **revivable
by the next stranded XXL owner**, favor "anyone can follow the guide" over
builder-only convenience.

## Hard constraints
- **The frame is real, but remote.** Hardware is no longer a blocker: the wiped
  mini PC runs the OpenObject Linux kiosk, verified on Matt's actual XXL, with
  over-the-air self-update. But it is **not reachable from this dev environment**
  (sandboxed, no LAN access). For any on-frame op (SSH, `scp`, `systemctl`, kiosk),
  hand Matt the exact command to run; do **not** try to run it here. Day-to-day app
  work is still done browser-visible on macOS.
- **Two docs, kept in lockstep.** Any change to user-facing behavior updates
  **`docs/SETUP-GUIDE.md`** in the *same change* as `docs/HANDOFF.md`. The Setup
  Guide must always reflect shipped behavior (HANDOFF §16).
- **Don't invent hardware specs.** Most §19 bench items are now confirmed on the
  real frame (models, BIOS-entry key, CPU, eMMC, Wi-Fi module, the 1920×1920 panel);
  the lone open one is **RAM**. Mark any genuinely-unknown spec as a clear
  placeholder rather than guessing, this is a public repo.
- **Art never touches the repo.** Uploaded images/videos and the local library are
  gitignored runtime data, never committed (HANDOFF §8, §15).
- **Repo is PUBLIC but PROPRIETARY** (all rights reserved; source is public, **not**
  "open source", and not licensed for reuse; see `LICENSE`). Copyright **Queueue Studios
  LLC**. Say "source is public, all rights reserved", never "open source" or
  "source available for noncommercial use". The next-owner mission still drives design:
  owners may run it to revive their own frame.

## Git workflow
- Claude runs **all** `git`/`gh` commands; Matt never types them.
- Work in **logical checkpoints**. At each, show staged changes + commit message,
  then commit **and** push together **on Matt's OK**. No per-commit nagging.
- **Outward-facing actions are gated**: creating the repo and pushing always get an
  explicit confirm first.
- Commits carry the standard `Co-Authored-By: Claude` trailer.

## Confirmed v1 decisions
- **Content model: Library + select** (§7). Uploads add to a persistent **Library**;
  the user curates a **Rotation** (an ordered subset) and may **Pin** one clip to
  hold permanently. (Chosen over replace-on-upload.)
- **Stack: Node.js + Express + vanilla HTML/CSS/JS + SQLite. No build step.** One
  language across server and the browser display page; maximally revivable. The app
  lives in `player/`.
- **Display surface: edge-to-edge, zero chrome.** Full-panel black stage
  (`100vw × 100vh`, no margin/padding/border/scrollbars/UI). Media renders to the
  physical edges. **No decorative frame or border, ever.**
- **Render mode: default Fit** (original aspect ratio, `object-fit: contain`);
  **per-clip Fill override** (`object-fit: cover; object-position: center`,
  symmetric center-crop). Fit letterboxes against black, that bare stage is *not* a
  frame. v1 is center-crop only.
- **Rotation order: Sequence / Shuffle.** Sequence = the set order; Shuffle =
  randomized pass, each clip once before repeating, then reshuffles. (Pure independent
  Random was dropped, odd fit for a frame; Shuffle already covers random order.)
- **Motion: GIF/WebP/AVIF/SVG and video loop-to-fill; never freeze on frame 1.**
  **One global equal-time duration** for every piece (no per-clip duration); a clip
  longer than it is cut at the duration, shorter loops to fill.
- **Audio: uploaded video is muted; Connected pieces are per-collection** (HANDOFF §12,
  revised 2026-07-20). The old "muted, always" rule dates from when the speakerless XXL
  was the only display; the Mac is primary now, so a scored piece can be heard. A
  collection may expose its own audio control (*The Bloom* carries **Music**, default
  On, because its soundtrack drives what the piece renders). The XXL frame opens no
  audio output at all, verified on the real device, so audio is inert there.
- **Storage: full local mirror by default.** Progressive sync: start the rotation on
  the first clip, fold the rest in without restarting/stuttering the loop. A
  buffered/least-recently-shown eviction mode is a documented seam, off by default.
- **Source layer is a clean interface.** v1 ships **web upload** and **Connected
  Collections**, a curated on-chain/NFT resolver that is now a **core feature** (HANDOFF
  §8). SMB pull stays an optional seam (not built); a general "paste any URL" / live
  on-chain resolver was considered and **dropped** (HANDOFF §17/§20).
- **Sleep Schedule** (optional overnight/away blank/dim, by day of week) is a v1 feature.

## Formats (v1)
Supported: **JPEG, PNG, GIF, AVIF, WebP, SVG, MP4, MOV, WebM**. PNG transparency renders
against black. **SVG renders as a safe `<img>`** (its scripts/external refs never run; SMIL/CSS
animation still loops; a clean `viewBox` scales and centers on black). **Skip** (do not convert,
do not error) everything else, HEIC, PSD, raw, GLB, and OS noise (`.DS_Store`, office files,
etc.). Uploads stay byte-for-byte.

## Branding
The **OPEN / OBJECT** wordmark lives in `assets/branding/`: **`openobject-logo.svg`**
(single-color, transparent, traced from the high-res master with Potrace) plus its PNG
exports (`openobject-logo-256/512.png`, favicons, apple-touch-icon). Large source masters
stay in `Logo/` (gitignored). CSS recolors the SVG white-on-dark (idle/boot screen) or
black-on-light; it is wired into the player's display and control pages. A plain raster
color-inverse is *not* the plan (Matt handles that in Photoshop if ever needed). **SVG
here is a UI/brand asset**; displayed user *art* in SVG is supported too, rendered as a
safe image (see Formats / §6). Aesthetic: understated, functional, no clutter.

## Phases
The phases are layers, not a queue: both the app and the frame kiosk are live today.
- **Phase 0** (repo, structure, docs, GitHub): **done.**
- **Phase 1**, the web app (server, library/upload, control panel, display + behaviors,
  progressive sync, sleep schedule, Connected Collections, self-update from GitHub):
  **done, shipped as v1.0.0.** Runs browser-visible on macOS or any computer.
- **Phase 2**, the frame (Debian-based Linux, Chromium kiosk, Avahi/mDNS, BIOS
  Auto-Power-On, real device power, the install path): **built and verified on the real
  XXL**, with OTA self-update. A few later milestones remain (authoritative list in the
  HANDOFF status line + §20): notably a **single-file/prebuilt release image** (USB
  installer as a GitHub Release asset) and **Wi-Fi onboarding** (AP + captive page).
  SMB pull stays an optional seam.

## Running the player
```
cd player && npm install && npm start
```
Then open **http://localhost:3000/**, the control panel (Library, Rotation, Settings,
Connected Collections, Sleep, Software Update). The kiosk display is at **/display**
(black, edge-to-edge stage; the branded idle screen until art is in the rotation).
Separate routes, so the Chromium kiosk on the frame points straight at the display.

Uses Node's built-in **`node:sqlite`** (Node ≥ 22.5), no native module, no build step.
Runtime data (the library DB under `player/data/`, uploads) is gitignored (HANDOFF §8).

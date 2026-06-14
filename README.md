<p align="center">
  <img src="assets/branding/openobject-logo-512.png" alt="OpenObject" width="300">
</p>

# OpenObject

Self-hosted replacement software for the **Infinite Objects XXL** — the 26" square
digital art frame whose original "White Walls" cloud software has decayed.
OpenObject wipes the frame's built-in mini PC and turns it into a clean, **local**
art player: it shows your own images and videos, is controlled from a web page in
any browser, and **depends on no external service** to keep running.

> **Status — working on real hardware.** The web app (control panel + display) and a
> Debian-based installer are built and verified on an actual XXL: the frame boots with
> no desktop straight into the art, reachable at `http://openobject.local`. The source
> is available for **noncommercial use** — see [License](#license).

## Why
The XXL is a normal x86 mini PC (a **MeLE Quieter 3Q**) behind a square panel — not
a sealed appliance. When the vendor went quiet, perfectly good hardware was left
showing error screens. OpenObject is a software reflash that brings it back, with
two commitments:

1. **Self-contained on the player.** The mini PC is the always-on brain. Your
   Mac/phone are just where files come *from* and a browser to control it.
2. **Revivable by the next owner.** This is meant as a shareable kit, so *anyone*
   with a stranded XXL can follow along and bring their own unit back.

## What it does (v1)
- Displays **JPEG, PNG, GIF, AVIF, WebP, MP4, MOV, WebM**, edge-to-edge on the square
  panel — no frame, no border.
- **Library + Rotation + Pin:** everything you upload is kept; you choose what's in
  the cycle and in what order (**Sequence / Shuffle**), and can pin one piece to hold
  permanently.
- **Per-clip control:** one global hold duration, and **Fit** (whole image — the
  default) vs **Fill** (crop to fill the square).
- **Animated art and video always loop** to fill their time — never freeze on the
  first frame. Silent by design.
- **Sleep hours** to blank the panel overnight.
- Add art by **dragging files onto the control panel** from any device — no
  accounts, no cloud.
- **Updates itself** from this repo (control panel → *Check for updates*), no reflash.

## Hardware target
|              |                                                                    |
| ------------ | ------------------------------------------------------------------ |
| Frame        | Infinite Objects XXL (26", 1:1 square — 1920×1920)                  |
| Player       | MeLE Quieter 3Q — Intel Celeron **N5105** (x86-64), Wi-Fi + Gigabit |
| Video path   | Captive HDMI from the mini PC to the panel — untouched by reflash   |

## Get started
- **Reviving a frame?** The **[Setup Guide](docs/SETUP-GUIDE.md)** walks the whole thing
  in plain language. Builders: **[installer/](installer/README.md)** has the bench runbook
  (wipe the eMMC, install minimal Debian, run `install.sh`, boot into the kiosk).
- **Just want to try the app on your Mac?** `cd player && npm install && npm start`, then
  open `http://localhost:3000/` (needs Node ≥ 22.5).

## Repository layout
```
docs/        engineering spec (HANDOFF) + casual SETUP-GUIDE + appendixes
player/      the OpenObject web app (Node + SQLite, no build step)
installer/   the Debian + Chromium-kiosk installer for the frame
assets/      branding (the OpenObject mark)
```

## Documentation
- **[Setup Guide](docs/SETUP-GUIDE.md)** — for owners reviving a unit (no engineering).
- **[Handoff / Build Spec](docs/HANDOFF.md)** — the full engineering spec + decision log.
- **[Installer runbook](installer/README.md)** — how the frame is provisioned.
- **[White Walls reset appendix](docs/appendix-whitewalls-reset.md)** — restoring the
  *original* software, for owners who want it back.

## License
**Source available for noncommercial use** — [PolyForm Noncommercial License 1.0.0](LICENSE).

In plain terms: you may use, modify, and share OpenObject to revive and run **your own**
frame — personal and hobby use is welcome. You **may not** sell it, charge for it, or build
it into a product, service, or other commercial/revenue venture. Because of that noncommercial
limit it is deliberately **not** "open source" in the OSI sense — it is *source available*.

<p align="center">
  <img src="assets/branding/openobject-logo-512.png" alt="OpenObject" width="300">
</p>

# OpenObject

OpenObject is a self-hosted, borderless art display for your Mac. It turns any Mac and an everyday
monitor into an edge-to-edge digital canvas you control from your phone or any browser on your
network. No cloud, no account, no subscription.

**[Download for Mac](https://github.com/queueue-studios/openobject/releases/latest)** · [openobject.io](https://openobject.io)

## How it works

You upload your art, and OpenObject shows it edge to edge on a monitor. Your everyday screen becomes
the art. You manage everything (what is in the rotation, timing, sleep schedule) from any browser on
your network, through the control panel.

Under the hood it runs as a small local art player (technically a lightweight server) on your Mac,
and presents the art in a Chromium kiosk: no window, no menus, no toolbars, just art filling the
screen. Everything stays on your network.

We built OpenObject to deliberately avoid the APIs, infrastructure, and wallet connections needed to
read art directly from the blockchain. Instead, you keep a local copy of your art and upload it.
Everything is local. Simple, safe, and secure.

## What it does

- Displays **JPEG, PNG, GIF, AVIF, WebP, SVG, MP4, MOV, WebM**, edge to edge, no border.
- **Library, Rotation, and Pin.** Everything you upload is kept. You choose what plays and in what
  order (Sequence or Shuffle), and can pin one piece to hold it permanently.
- **Fit or Fill.** One global hold duration, plus Fit (the whole image, the default) or Fill (crop
  to fill the screen).
- **Animated art and video always loop** and never freeze on the first frame. Silent by design.
- **Sleep Schedule** to rest the screen by time of day and day of week.
- Add art by **dragging files onto the control panel** from any device.
- **Connected Collections.** A curated handful of generative and on-chain artworks (like a p5.js
  sketch that renders live), mirrored locally so they play offline. Curated, not a general NFT reader.
- **Built-in updates.** Check for Updates installs the latest version, no reinstall.

## Requirements

- A **Mac** (macOS 15 or later) and a monitor to display on (the Mac's own screen or an external one).
- **Google Chrome** installed. OpenObject drives it in kiosk mode to render the art; you never see or
  use it as a browser.

## Get started

**[Download OpenObject for Mac](https://github.com/queueue-studios/openobject/releases/latest)**, open
the `.dmg`, and drag OpenObject to Applications. The [Mac guide](docs/MAC-DISPLAY-SETUP.md) walks the
first run.

> ### Have an Infinite Objects XXL frame?
> OpenObject can revive one too. This is where OpenObject started: we built it to bring a stranded XXL
> back to life, and kept the code and a full guide so any owner can do the same. It is an advanced,
> hands-on path (a from-scratch install on the frame's mini PC), separate from the Mac app.
>
> → **[Reviving an Infinite Objects XXL](docs/SETUP-GUIDE.md)**

## On displaying art you love

Anyone can view digital art in a browser, download it, or screenshot it. That has always been true,
and it is not what OpenObject changes. Viewing art and displaying art you own are different things.
OpenObject is built to display art you own, or otherwise have the right to display, and it is intended
for home use. If you display art in public, please make sure you have a license to do so. We
deliberately avoided wallet connections and their complexity: the process is simply to save a local
copy of your art and upload it to OpenObject to display it.

## One core, many ways to run it

The Mac app today, an Infinite Objects XXL frame, and, ahead, Apple TV and iPad. Because the core is
just a small local art player, it is not locked to any one device (technically minded owners can even
run it on their own hardware).

## Documentation

**On your Mac**
- [Mac guide](docs/MAC-DISPLAY-SETUP.md): install and first run.

**Reviving an Infinite Objects XXL frame** *(advanced)*
- [Reviving an XXL frame](docs/SETUP-GUIDE.md): the full walkthrough, in plain language.
- [Installer runbook](installer/README.md): bench provisioning (wipe, Debian, install).
- [Returning a frame to its original software](docs/appendix-original-reset.md): untested and
  unsupported, and only possible if you backed up first. At your own risk.

**Reference**
- [Handoff / Build Spec](docs/HANDOFF.md): the engineering spec and decision log.

## License

**Proprietary. All rights reserved.** The source is public, but OpenObject is not open source, and
publishing it grants no license to reuse it. See the full [License](LICENSE).

In plain terms: you may download, install, run, and update OpenObject to power **your own** display
or frame, for personal noncommercial use. Without a separate written license from Queueue Studios
LLC you **may not** use it (or any of its source) in a commercial product, service, or venture,
redistribute or host it for others, or modify and distribute it. All other rights are reserved.

## No warranty

OpenObject is provided **as is**, with **no warranty of any kind**. To the fullest extent permitted
by law, Queueue Studios LLC is **not responsible** for what you do with OpenObject, for what it does
or fails to do, or for any resulting damage, data loss, or other harm, and makes **no guarantee**
that it works or will keep working.

**Running it on your own computer** (a Mac, for example) is simple. It is just an app you start
and stop, kept in its own folder, and you can delete it whenever you like. It does not wipe or
alter the rest of your machine.

**Reviving an Infinite Objects frame is the part with real risk.** That path **wipes the frame's
storage**, with no supported way back. It may not work on your exact unit, it may stop working
after an update or over time, and in the worst case it could leave the frame unusable. You take
that risk yourself.

## Independence and trademarks

OpenObject is an independent project, written from scratch. It contains no source code, assets,
or data from the device's original manufacturer or any original software provider, and
incorporates none of it. Installing OpenObject on a frame erases the frame's storage, removing all
original software and data before OpenObject is installed.

OpenObject is not affiliated with, authorized by, or endorsed by the device's original
manufacturer or any original software provider. Product and company names that appear elsewhere
in this project are the property of their respective owners and are used only to identify the
hardware and the original software OpenObject replaces.

# OpenObject — Setup Guide

A plain-English guide for reviving an **Infinite Objects XXL** frame with OpenObject.
No engineering knowledge needed. If you've never seen the build spec, you're in the
right place.

> **Heads-up — this guide is still being written.** The everyday "add and arrange
> art" part (further down) is real and current. The **install** part now has a working
> installer (built 2026-06-14) and is being tested on the real frame at the bench. The
> hardware is confirmed — the BIOS key (**`Del`**) and the exact parts are filled in
> below. The goal is a **single download you flash once**; until that one-file image is
> ready, installing means a couple of extra steps (builders: see `installer/README.md`).
> The steps below will get final screenshots and a tested image before anyone relies on
> them. Nothing here is final until this note is gone.

---

## What you need before you start

- A working **Infinite Objects XXL** (the 26" square frame) with its **MeLE Quieter
  3Q** mini PC on the back.
- **USB hub** — UGreen USB 3.0 Hub, 4-port (model **25946**).
- **Left-angle USB-A extension** — CableCreation USB 3.0 Extension, Left Angle, 1 ft
  (part **CC0516**). The **left** angle matters: it tucks the cable away from the power
  socket that sits right next to the USB port.
- **USB keyboard** — Logitech **K400 Plus** (a keyboard with a built-in touchpad, one
  USB receiver — so you don't need a separate mouse).
- **USB flash drive**, 16 GB or larger — for the installer.
- **External USB drive**, 128 GB or larger — **optional**, _only_ if you want to make a
  one-time backup of the original software first (a USB SSD is ideal; exFAT format works
  everywhere). See the **[backup appendix](appendix-backup-original.md)**.

---

## Installing OpenObject (one time)

> These steps are kept in sync with the real procedure as it's finalized.

> **⚠️ Important — don't touch the two screws above the mini PC.** While you're working
> at the back of the frame, leave alone the two screws on the bracket just **above** the
> MeLE mini PC. Loosening or removing them lets nuts drop down inside the frame, and
> getting them back means taking most of the unit apart. They aren't part of any step below.

1. Plug the left-angle extension into the mini PC's free USB port; attach the hub;
   attach the keyboard and the installer flash drive.
2. Power on and open the **BIOS**: tap **`Del`** as it starts up. (The frame's logo
   hides the prompt, so just tap `Del` a few times while the screen is still black.)
   Set it to boot from the USB drive. _(There's no "Auto Power On" to switch on — this
   frame already starts by itself whenever it has power.)_
3. Boot the installer. *(Optional: to keep a copy of the original software first, see
   the [backup appendix](appendix-backup-original.md) — most owners skip this.)*
4. Install OpenObject and wait for the frame to show the **OpenObject** screen.
5. On your phone, join the temporary **OpenObject-Setup** Wi-Fi network. A setup page
   opens automatically — pick your home Wi-Fi and enter the password. The frame
   switches over to your network.
6. On any device, open **http://openobject.local** in a browser. (If that doesn't
   work — e.g. on some Windows PCs — use the IP address shown on the setup page.)

That's it. From here on you control everything from that web page.

---

## Using OpenObject day to day

Everything happens at **http://openobject.local** — the control panel. Open it from
your Mac, iPhone, iPad, or PC.

**Add art.** On the **Library** tab, drag image or video files onto the page, or tap to
choose them. They upload straight to the frame. Supported types: **JPEG, PNG, GIF, AVIF,
WebP, MP4, MOV, WebM**. Anything else is simply skipped — nothing is changed or converted.

**Your Library vs the Rotation.** Everything you upload stays in the **Library**. The
**Rotation** is the set that's actually showing on the wall. The control panel has three
tabs:
- **Library** — everything you've uploaded. Tap the small circle in the top-right
  corner of any piece to add it to (✓) or remove it from (+) the Rotation.
- **Rotation** — just what's playing, in order, plus how long each piece shows and
  Sequence/Shuffle. New uploads join the Rotation automatically, so you can keep a growing
  collection and still show just today's pick by removing the rest.
- **Settings** — sleep hours, software updates, and frame controls (restart, shut down, Wi-Fi) (below).

**Order.** Choose how the Rotation plays:
- **Sequence** — in the order you arrange them. In the **Rotation** tab, drag a piece by
  its handle, or use the **↑ / ↓** buttons, to reorder it; the **✕** takes it out of the
  Rotation.
- **Shuffle** — randomized, but each piece shows once before any repeats. (Your arranged
  order is kept for whenever you switch back to Sequence.)

**Pin one piece.** Want a single image up permanently? **Pin** it and it holds on the
screen until you unpin.

**How each piece fills the square.** The frame is square; most art isn't. Per piece:
- **Fit** *(default)* — shows the whole image at its real shape; the rest of the screen
  stays black. Nothing is cut off.
- **Fill** — zooms the image to cover the whole square, trimming the edges evenly.

Either way there's **no border** — the art (or the black surround) goes right to
the edges of the screen.

**Duration.** Set **one time** — in **seconds, minutes, or hours** — that applies to
**every** piece, the same for each (no per-piece timing). Videos and animations always **loop** and never freeze on the first
frame: a shorter one repeats to fill the time, and a clip longer than the time simply
moves on when it's up.

**Sound.** Always off. It's silent art on a wall.

**Sleep hours** *(in the **Settings** tab)*. Optionally have the screen rest on a schedule —
you get **two time ranges**, each with its own on/off checkbox, so you can cover both "while I'm at work"
and "overnight." Set them on a normal **12-hour clock** (AM/PM). While asleep, the screen
shows the OpenObject logo dimmed and stops playing, then picks the rotation back up on its
own. **Want it off right now?** Tap **Blank screen** at the top of the control panel — the
art goes dark until you tap it again.

**Restart or shut down** *(Settings tab)*. **Restart** restarts the OpenObject software —
handy if the app seems stuck. (It doesn't reboot the frame's hardware; for that, power-cycle
the outlet.) **Shut down** turns off the frame (this works once OpenObject is installed on the
frame). Neither needs you to reach behind it.

**Reaching the frame** *(Settings → Wi-Fi)*. The frame sets up its own Wi-Fi on first
boot so you can put it on your home network. The Wi-Fi section also lists the addresses
you can open the control panel at from another device.

---

## Keeping OpenObject up to date

OpenObject can update itself — no cables, no reinstalling. It lives in the **Settings**
tab of the control panel, under **Software Update**, which shows the version you're
running (a version number and the date it's from).

Tap **Check for updates**. If a newer version is available you'll see a short list of
what's in it (plus a **What's new** link for the full details); tap **Update & Restart**.
The frame briefly shows the OpenObject screen and comes back on the new version — **your
art and settings are kept**. Updates only happen when you ask; nothing changes on its own,
and the frame just needs to be online to check. Not ready? **Not now** dismisses it.

- If the frame ever says it has **local changes** and can't update automatically, that's a
  safety stop so nothing of yours gets overwritten — your art keeps playing either way, and
  you can ask whoever set the frame up about it.

---

## If something seems stuck

- The frame restarts itself whenever it gets power, so a quick **power cycle at the
  outlet** (or a smart plug) fixes most hiccups.
- For normal restarts, use the **Restart** button in the control panel.
- If the control panel won't load, re-check that your device is on the same Wi-Fi as
  the frame, and try the **IP address** shown during setup instead of
  `openobject.local`.

---

## Want the original software back?

If you'd rather return to the original "White Walls" experience, see
**[the White Walls reset appendix](appendix-whitewalls-reset.md)**. The most complete way
to preserve the original is to **[back up its drive](appendix-backup-original.md)** before
you install OpenObject (optional, capture-only).

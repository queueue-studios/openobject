# OpenObject — Setup Guide

A plain-English guide for reviving an **Infinite Objects XXL** frame with OpenObject.
No engineering knowledge needed. If you've never seen the build spec, you're in the
right place.

> **Heads-up — this guide is still being written.** The everyday "add and arrange
> art" part (further down) is real and current. The **install** part needs the
> bootable USB installer, which is built once the project's bench hardware arrives —
> those steps below are the plan and will be finalized (with the exact BIOS key and
> screenshots) before anyone follows them. Nothing here is final until this note is
> gone.

---

## What you need before you start

- A working **Infinite Objects XXL** (the 26" square frame) with its **MeLE Quieter
  3Q** mini PC on the back.
- **USB hub** — _[exact make/model — TBD, confirmed once it's fit-tested in the unit's clearance]_
- **Right-angle USB-A extension** — _[exact make/model — TBD; a CableCreation L+R 2-pack was ordered; the one that fits gets recorded here]_
- **USB keyboard** — _[exact make/model — TBD; a Logitech K400 Plus was the plan]_
- **USB flash drive**, 16 GB or larger — for the installer.
- **External USB drive**, 128 GB or larger — _only_ if you want to back up the
  original software first.

---

## Installing OpenObject (one time)

> These steps are kept in sync with the real procedure as it's finalized.

> **⚠️ Important — don't touch the two screws above the mini PC.** While you're working
> at the back of the frame, leave alone the two screws on the bracket just **above** the
> MeLE mini PC. Loosening or removing them lets nuts drop down inside the frame, and
> getting them back means taking most of the unit apart. They aren't part of any step below.

1. Plug the right-angle extension into the mini PC's free USB port; attach the hub;
   attach the keyboard and the installer flash drive.
2. Power on and open the **BIOS** _(key: TBD — usually `DEL`, `ESC`, or `F7`)_. Set
   it to boot from the USB drive, and turn on **Auto Power On** so the frame starts
   by itself whenever it has power.
3. Boot the installer. *(Optional: back up the original software first if you have
   the external drive.)*
4. Install OpenObject and wait for the panel to show the **OpenObject** screen.
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
- **Settings** — sleep hours and software updates (below).

**Order.** Choose how the Rotation plays:
- **Sequence** — in the order you arrange them. In the **Rotation** tab, drag a piece by
  its handle, or use the **↑ / ↓** buttons, to reorder it; the **✕** takes it out of the
  Rotation.
- **Shuffle** — randomized, but each piece shows once before any repeats. (Your arranged
  order is kept for whenever you switch back to Sequence.)

**Pin one piece.** Want a single image up permanently? **Pin** it and it holds on the
panel until you unpin.

**How each piece fills the square.** The frame is square; most art isn't. Per piece:
- **Fit** *(default)* — shows the whole image at its real shape; the rest of the panel
  stays black. Nothing is cut off.
- **Fill** — zooms the image to cover the whole square, trimming the edges evenly.

Either way there's **no frame or border** — art (or the black surround) goes right to
the edges of the panel.

**Duration.** Set **one time** — in **seconds, minutes, or hours** — that applies to
**every** piece, the same for each (no per-piece timing). Videos and animations always **loop** and never freeze on the first
frame: a shorter one repeats to fill the time, and a clip longer than the time simply
moves on when it's up.

**Sound.** Always off. It's silent art on a wall.

**Sleep hours** *(in the **Settings** tab)*. Optionally have the panel rest on a schedule —
you get **two time ranges**, each with its own on/off checkbox, so you can cover both "while I'm at work"
and "overnight." Set them on a normal **12-hour clock** (AM/PM). While asleep, the panel
shows the OpenObject logo dimmed and stops playing, then picks the rotation back up on its
own. **Want it off right now?** Tap **Blank panel** at the top of the control panel — the
art goes dark until you tap it again.

**Restart or shut down.** Buttons in the control panel — no reaching behind the frame.

---

## Keeping OpenObject up to date

OpenObject can update itself — no cables, no reinstalling. It lives in the **Settings**
tab of the control panel, under **Software Update**, which shows the version you're
running (a version number and the date it's from).

Tap **Check for updates**. If a newer version is available you'll see a short list of
what's in it (plus a **What's new** link for the full details); tap **Update & Restart**.
The panel briefly shows the OpenObject screen and comes back on the new version — **your
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
**[the White Walls reset appendix](appendix-whitewalls-reset.md)**. (Backing up the
original install during step 3 above is the most complete way to preserve it.)

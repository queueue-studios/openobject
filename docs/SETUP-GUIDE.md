# OpenObject Setup Guide

A plain-English guide for reviving an **Infinite Objects XXL** frame with OpenObject. No
engineering knowledge needed. If you've never seen the build spec, you're in the right place.

**Home base:** [openobject.io](https://openobject.io)

> **Most people don't need this guide.** OpenObject is a Mac app: download it and your Mac drives the display. That is the main way to use it, covered in **[Set up OpenObject on your Mac](MAC-DISPLAY-SETUP.md)**. This guide is a separate, advanced job: reviving **Infinite Objects XXL** hardware with a from-scratch install on the frame's mini PC.

## So you want to try this?

A frank word, friend to friend, before you start.

I went in considering my XXL **useless**. The backend services it relied on had wound down, and the frame was a
paperweight, so I had nothing to lose. Whatever happened, it cost me nothing I hadn't already
written off. **Bring that mindset.** If your frame still works and you'd grieve losing it, think
hard first.

A few honest caveats:

- **Your hardware may not be exactly mine.** I can't be certain your unit, or the settings
  Infinite Objects shipped it with, match what I had. Yours could differ in ways I never hit.
- **Your computer and network aren't mine either.** I did this from a Mac, on my own network. I
  can't assume you have the same machine, the same Wi-Fi, or the same setup, so some steps may
  land differently for you.
- **I won't pretend it was easy. It wasn't.** Be prepared to toil through some issues. I leaned
  on Claude Code to navigate the rough patches, and honestly that's what got me through. I'm glad
  to help where I can, but I'm one guy who revived his own frame, not a customer-service desk.
  Please don't expect me to be one.
- **That said, it is built to be as painless as possible for you,** the person coming next. A lot
  of the work went into smoothing the path so you hit fewer walls than I did.

What you get today: OpenObject makes the XXL a **highly effective, accessible digital frame**.
Your own images and video, edge to edge, run from your phone. It is **not** a general blockchain or
NFT reader, though it now has **curated support for a few specific collections** (see
"Connected Collections" below).

> **No warranty.** OpenObject is provided as is, with no warranty of any kind. Installing it wipes
> your device and there is no supported way back. You take that risk yourself. The full notice is
> in the [README](../README.md#no-warranty).

---

## What you need before you start

- A working **Infinite Objects XXL** (the 26-inch square frame) with its **MeLE Quieter 3Q** mini
  PC on the back.
- **USB hub:** UGreen USB 3.0 Hub, 4-port (model **25946**).
- **Left-angle USB-A extension:** CableCreation USB 3.0 Extension, Left Angle, 1 ft (part
  **CC0516**). The left angle matters: it tucks the cable away from the power socket that sits
  right next to the USB port.
- **USB keyboard:** Logitech **K400 Plus** (a keyboard with a built-in touchpad on one USB
  receiver, so you don't need a separate mouse).
- **USB flash drive,** 16 GB or larger, for the installer.
- **External USB drive,** 128 GB or larger. Optional, only if you want a one-time backup of the
  original software first (a USB SSD is ideal; exFAT format works everywhere). See the
  [backup appendix](appendix-backup-original.md).

---

## Installing OpenObject (one time)

> **Heads-up: this is a hands-on install.** You put a minimal Debian Linux on the frame, then
> run the OpenObject installer over it. The complete, current step-by-step lives in the
> **[installer runbook](../installer/README.md)**. The outline below is just the shape of it.

> **Important: don't touch the two screws above the mini PC.** While you're working at the back of
> the frame, leave alone the two screws on the bracket just above the MeLE mini PC. Loosening or
> removing them lets nuts drop down inside the frame, and getting them back means taking most of the
> unit apart. They aren't part of any step below.

1. Plug the left-angle extension into the mini PC's free USB port, attach the hub, then attach the
   keyboard and the installer flash drive.
2. Power on and open the **BIOS** by tapping **`Del`** as it starts up. (The frame's logo hides the
   prompt, so just tap `Del` a few times while the screen is still black.) Set it to boot from the
   USB drive. There is no "Auto Power On" to switch on; this frame already starts by itself whenever
   it has power.
3. Boot the installer and follow the **[installer runbook](../installer/README.md)**: install a
   minimal Debian, then run the OpenObject installer, which sets everything up and reboots into the
   art. You join your home Wi-Fi during this install. (Optional: to keep a copy of the original
   software first, see the [backup appendix](appendix-backup-original.md). Most owners skip it.)
4. When it finishes, the frame boots straight to the **OpenObject** screen. (On every power-up you'll briefly see the Infinite Objects logo first. That's the frame's own built-in startup logo, not OpenObject, and it's completely normal, it does not mean anything went wrong.)
5. On any device, open **http://openobject.local** in a browser. If that doesn't work, for example
   on some Windows PCs, use the IP address shown in the control panel.

That's it. From here on you control everything from that web page.

---

## Using OpenObject day to day

Everything happens at **http://openobject.local**, the control panel. Open it from your Mac,
iPhone, iPad, or PC.

**Add art.** On the **Library** tab, drag image or video files onto the page, or tap to choose
them. They upload straight to the frame. Supported types: **JPEG, PNG, GIF, AVIF, WebP, SVG, MP4, MOV,
WebM**. Anything else is simply skipped, with nothing changed or converted. Very large files (over
512 MB) are skipped as well, and if the frame is low on storage it will ask you to remove some art
before adding more.

**Name your art (optional).** An uploaded piece shows its filename until you give it a title. Tap the
name on its Library card to edit the **title** and **artist**, then Save (or press Enter); leave a field
blank to fall back to the filename. Add a single file and its card opens ready to name. (Connected pieces
already carry their own title and artist.) These labels are for organizing in the control panel; they
never appear over the art.

**Your Library vs the Rotation.** Everything you upload stays in the **Library**. The **Rotation**
is the set that's actually showing on the wall. The control panel has three tabs:

- **Library:** everything you've uploaded. Tap the small circle in the top-right corner of any
  piece to add it to (checkmark) or remove it from (plus) the Rotation.
- **Rotation:** just what's playing, in order, plus how long each piece shows and Sequence or
  Shuffle. New uploads join the Rotation automatically, so you can keep a growing collection and
  still show just today's pick by removing the rest.
- **Settings:** sleep schedule, connected collections, software updates, frame controls (restart, shut down), an optional password, a name for the frame and how to reach it on your network, and an About section,
  described below.

**Sort your Library.** As your collection grows, use the **Sort** control on the right of the Library
tab to order the grid by **Recent** (newest first, the default), **Oldest**, **Title** (A to Z), or
**Artist** (A to Z, with pieces that have no artist last). Your choice stays until you change it.

**Show just what's playing.** Next to Sort is a **Show** control. Leave it on **All** to see everything,
or switch it to **In rotation** to hide the pieces that aren't currently playing. That's handy once your
Library has grown and you only want to see today's set. Nothing is deleted, switch back to **All** any
time and the rest reappear.

**A sample to start.** Your Library comes with one piece already in it, the **Bouncing OpenObject Logo**
(the OpenObject wordmark drifting around the screen, an homage to the old DVD screensaver). It starts **out of
the Rotation**, so a brand-new player opens on the OpenObject screen (the logo, with an "add art" hint) instead
of jumping straight into the sample. Add it to the Rotation whenever you want to watch it, or just leave it as
an example and build your Rotation from your own art. It always sits at the bottom of the Library, whichever
sort you pick, as the piece that came with your player, and you can remove it like any other piece.

**Order.** Choose how the Rotation plays:

- **Sequence:** in the order you arrange them. In the **Rotation** tab, drag a piece by its handle,
  or use the up and down buttons, to reorder it. The **X** takes it out of the Rotation.
- **Shuffle:** randomized, but each piece shows once before any repeats. (Your arranged order is
  kept for whenever you switch back to Sequence.)

**Pin one piece.** Want a single image up permanently? **Pin** it and it holds on the screen until
you unpin.

**How each piece fills the square.** The frame is square; most art isn't. Per piece:

- **Fit** *(default)*: shows the whole image at its real shape, with the rest of the screen black.
  Nothing is cut off.
- **Fill:** zooms the image to cover the whole square, trimming the edges evenly.

Either way there is **no border**. The art (or the black surround) goes right to the edges of the
screen.

**Duration.** Set **one time**, in **seconds, minutes, or hours**, that applies to **every** piece,
the same for each (no per-piece timing). Videos and animations always **loop** and never freeze on
the first frame: a shorter one repeats to fill the time, and a clip longer than the time simply
moves on when it's up.

**Sound.** Always off. It's silent art on a wall.

**Connected Collections**. Some digital art isn't a file you can download, it's a
generative or web-hosted piece. OpenObject can show a few **specific, supported collections** of this
kind. On the **Library** tab, tap **Add connected artwork**, pick the collection, and enter your
piece's **Token ID** (the number on the piece's page, for example OpenSea shows it as "Token #101").
For collections that only cover certain pieces, the add screen lists the **Supported Token IDs**, so you
know which numbers will work before you type one.
OpenObject looks up the real artwork, downloads it to the frame so it plays offline, and adds it as a
normal piece you can put in the Rotation or Pin like any other. If a connected piece ever looks wrong,
for example right after a software update, just remove it from the Library and add it again, that
rebuilds its downloaded copy from scratch. Some connected pieces even change
through the day on their own, for example one shifts from daytime colors to moonlit tones at night,
following your frame's local time. Another, Snowfro's *send/receive*, is a living piece that reads
its art network over the internet and animates non-stop, filling the whole panel edge to edge;
because it's live, this one looks its best when the frame is online (the others play fully offline
once they're added). One more, Juicy Julio's *Golden Lining*, is a desert photo that drifts between
black-and-white and full color; a simple speed slider lets you set how fast that drift moves, or rest
it on the full-color photo. Another, V4w.enko's *Perfect Everything*, is an ever-shifting pattern of
concentric colored rings that fills the whole panel and drifts on its own. The same artist's *Perfect Circles* is a companion series, slowly shifting concentric circles that fill the panel and drift on their own. And Cinzia y Gabriel's *Pendulum* is a
generative study of motion: a chain of colored orbs swings like a pendulum, tracing slow, ever-shifting arcs across the
whole panel. And Jeremy Booth's *Lost in Moffat County* is a series of painterly Western scenes that shift from day to
night on their own with your local time; switch on Animate for that piece (in Settings) to reveal a hand-drawn animated
easter egg. And Chaz Wesley's *The Bloom* is a hand-drawn flower garden that blooms at sunset, with a little
spaceship drifting through the sky above it. And NFTman76's *Binary Mountains* is a glowing wireframe
mountain range under a starry sky, with snow drifting down as the view slowly circles it; a **Snow**
setting (in Settings) lets you choose how heavy the snowfall is, from Light Snow to a full Blizzard.
And Erick Calderon (Snowfro)'s *Chromie Squiggle* is the original Art Blocks artwork: a bright,
ribbon-like squiggle of shifting colors on a clean white background. A speed slider (in Settings) sets how
fast its colors flow, starting at the original's gentle pace, turned up to lively, or held still; you can
switch its background between **White** (the original) and **Black**; and on its card you can choose
**Fit** to show the whole squiggle or **Fill** to enlarge it to fill the screen, trimming the edges.
The supported collections live in the **Settings** tab, under
**Connected Collections**, where you can hide ones you don't own and, for collections that have something to
adjust, turn their motion on or off, set sliders like speed or size, or choose a setting like the corner effect or snowfall. This is new and **curated**: only collections that have been
specifically added will work, so it won't read just any link yet.

**Folder Collections** *(in the **Settings** tab)*. Have a whole folder of art on your computer, say
hundreds of clips, that you'd rather not upload one at a time? A **Folder Collection** points OpenObject
straight at that folder and plays it in place. *(This works when a **computer is running OpenObject as
the display**. Showing a folder on the XXL frame itself is coming in a later update.)*

- **Set one up:** Settings, **Folder Collections**, **Add folder**, then pick the folder in the dialog
  that opens. OpenObject counts the compatible files in it (the same image and video types as uploads;
  anything else is ignored). Click the name to give it a **name** and optional **artist**, and choose
  **Fit or Fill** and **Sequence or Shuffle** for the whole folder. Nothing is copied; the files play
  right where they are.
- **Show it:** on the **Rotation** tab, use the **Source** dropdown to switch from **Library** to your
  folder. Your Library rotation pauses and the folder plays instead; switch back to **Library** any time
  and your rotation returns exactly as you left it. Only one source shows at a time.
- **It stays current:** add or remove files in the folder and OpenObject picks up the change on its own,
  no re-adding. Click a folder's **piece count** to open it and see what's inside.

Folders you save are remembered, so you can switch between them (and back to your Library) from the
Source dropdown any time.

**Sleep Schedule** *(in the **Settings** tab)*. Optionally have the screen rest on a schedule. Add up
to **three sleep times**, and for each one tap the **days** it applies to, so a weekday rest, a
weekend lie-in, and an "I'm at the office" block can all live side by side. Set the times on a normal
**12-hour clock** (AM/PM). A time that runs past midnight is tagged **"overnight,"** and its days
are the **nights it begins** (10:00 PM to 4:00 AM on Friday means Friday night into Saturday). A little
**week chart** underneath shades when the screen will sleep, so you can check the whole week at a glance.
While asleep, the screen shows the OpenObject logo dimmed and stops playing, then picks the rotation
back up on its own. **Want it off right now?** Tap **Sleep** at the top of the control panel; the same
button reads **Wake** while the screen is off. If you tap **Wake** during a scheduled sleep, the art
stays on until the next scheduled sleep.

The **Sleep Schedule**, **Connected Collections**, **Folder Collections**, **Password**, and **Network**
sections **start collapsed** to keep the Settings tab short. Tap a header to open one, and it stays the
way you leave it.

**Power** *(Settings tab)*. **Restart** restarts the OpenObject software, handy if the app seems
stuck. **Reboot** restarts the whole frame, and **Shut down** turns it off. If a control ever
doesn't take, you can always **power-cycle at the outlet**. None of them need you to reach behind
the frame.

**Password** *(Settings tab)*. The control panel is open to anyone on your home network by default, which is usually fine at home. If you'd like to lock it, set a password under Settings: after that, this device and any other will ask for it before making changes. The art on the wall keeps playing either way, and you can turn the password back off any time.

**Reaching the frame** *(Settings, Network)*. You set the frame's Wi-Fi while installing it. The
Network section of the control panel lists the addresses you can open it at from another device.
It also lets you give this frame a **name**, which is how it shows up on your network and in the
OpenObject app. Leave it blank to use the default. Naming is handy if you ever run more than one frame,
so they do not all look alike.

**About** *(Settings tab, at the bottom)*. A small card with the OpenObject name, a link to the
project home at openobject.io, a link to the source code on GitHub, and the license. If you ever
inherit this frame and want to understand or rebuild what it runs, that source link is where to start.

---

## Keeping OpenObject up to date

OpenObject can update itself, with no cables and no reinstalling. It lives in the **Settings** tab
of the control panel, under **Software Update**, which shows the version you're running (a version
number and the date it's from).

Tap **Check for updates**. If a newer version is available you'll see a short list of what's in it
(plus a **What's new** link for the full details), then tap **Update & Restart**. The frame briefly
shows the OpenObject screen and comes back on the new version, and **your art and settings are
kept**. The control panel then refreshes itself to the new version, so the changes show up right away.
Once in a while an update changes the on-screen display itself; when it does, the list tells you, and
you'll tap **Reboot** afterward to finish applying it.
Updates only happen when you ask, nothing changes on its own, and the frame just needs to be
online to check. Changes that don't run on the frame, like the docs or the website, won't appear
here, so a check that finds only those simply says you're up to date. Not ready? **Not now**
dismisses it.

If the frame ever says it has **local changes** and can't update automatically, that's a safety stop
so nothing of yours gets overwritten. Your art keeps playing either way, and you can ask whoever set
the frame up about it.

---

## If something seems stuck

- The frame restarts itself whenever it gets power, so a quick **power cycle at the outlet** (or a
  smart plug) fixes most hiccups.
- For normal restarts, use the **Restart** button in the control panel.
- If the control panel won't load, re-check that your device is on the same Wi-Fi as the frame, and
  try the **IP address** shown in the control panel instead of `openobject.local`.
- If the frame ever **drops off Wi-Fi** (the art is still on screen but the control panel won't load
  from any device), it now **re-joins on its own within about a minute**, so give it a moment before
  reaching for the power. A power cycle still fixes it right away if you're in a hurry.
- **To dig deeper, you can open a terminal (advanced, hands-on).** Plug a keyboard into the frame
  and press **Ctrl + Alt + F2** for a text login (use the username and password you set during
  install); **Ctrl + Alt + F1** returns to the art. Some keyboards treat the top row as media keys,
  so it may be **Ctrl + Alt + Fn + F2**. To work from another computer instead, OpenObject ships
  with SSH turned on, so you can connect straight to `openobject.local` (log in with the username
  and password you set during install). If you would rather keep it closed, turn it off with
  `sudo systemctl disable --now ssh`.

---

## Want the original software back?

If you'd rather return to the original experience, see the
**[original software reset appendix](appendix-original-reset.md)**. The most complete way to preserve
the original is to **[back up its drive](appendix-backup-original.md)** before you install
OpenObject (optional, capture-only).

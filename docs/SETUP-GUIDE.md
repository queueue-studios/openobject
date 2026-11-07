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

- A working **Infinite Objects XXL** (the 26-inch square frame) with its **MeLE** mini PC on the
  back: the **Quieter 3Q** it shipped with, or a **Quieter 4C** if the mini PC has been replaced
  (see [Replacing the mini PC](#replacing-the-mini-pc-advanced) below).
- **USB keyboard:** Logitech **K400 Plus** (a keyboard with a built-in touchpad on one USB
  receiver, so you don't need a separate mouse). Its receiver plugs into one of the **three USB
  ports on the side of the mini PC**, which are reachable with the unit in place. (An earlier
  version of this guide called for a hub and an angled extension cable, on the belief that only
  the port on the top edge was reachable. It is not so; neither is needed.)
- **USB flash drive** with a **USB-A** plug, 8 GB or larger, for the installer. Any brand.
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

1. Plug the keyboard's receiver and the installer flash drive into two of the USB ports on the
   side of the mini PC.
2. Power on and open the **BIOS** by tapping **`Del`** as it starts up. (The frame's logo hides the
   prompt, so just tap `Del` a few times while the screen is still black.) Set it to boot from the
   USB drive. On the original **Quieter 3Q** there is no "Auto Power On" to switch on; it already
   starts by itself whenever it has power. On a **Quieter 4C** there are two settings to make
   first: **Security, Secure Boot, set to Disabled**, and **Advanced, Customer Exclusive Functions,
   Auto Power On, set to Enabled**; a 4C out of the box does not start until its button is pressed,
   so press the button, then tap `Del`.
3. Boot the installer and follow the **[installer runbook](../installer/README.md)**: install a
   minimal Debian, then run the OpenObject installer, which sets everything up and reboots into the
   art. You join your home Wi-Fi during this install, and once the frame is online it downloads
   OpenObject itself, so there's nothing to prepare on your computer and no second USB drive. (Optional: to keep a copy of the original
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

**Sound.** A **Sound** setting (on the Rotation tab) is the master switch for whether the display makes
any noise, and it starts **On**. With it on, a video that came with sound plays that sound when your Mac
is the display, and a connected piece that came with music plays its music. Switch it to **Off** and the
whole screen goes quiet: your videos are muted, and a musical piece like Chaz Wesley's *The Bloom* shows
its calm, silent version (handy when you'd rather not re-level the TV's volume). Photos have no sound
either way. *The Bloom* also has its own **Music** setting (in Settings) that fine-tunes just that piece
when Sound is On; with Sound Off, the display's master switch wins and the piece stays silent regardless.
One quirk of ordinary web browsers: they don't let a page make sound until you've interacted with it, so
if you're watching in a plain browser tab rather than the built-in display, a video may stay muted and a
piece's music won't start until you **click the picture once**. A frame has no speaker, so it stays
silent there whichever way these are set.

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
its art network and animates non-stop, filling the whole panel edge to edge; like every other
connected piece it goes online once, when you add it, and from then on it shows the network as it was
that day, with no internet needed (remove it and add it again whenever you want a fresh look at the
network). One more, Juicy Julio's *Golden Lining*, is a desert photo that drifts between
black-and-white and full color; a simple speed slider lets you set how fast that drift moves, or rest
it on the full-color photo. The same artist's *Dark Radiance* is a photo of a desert dune that changes with
your frame's local time: a bright blue daytime sky from 7 am to 7 pm and a dark night sky the rest of the
time, with a short fade at each change. It's a landscape picture, so on a square frame it sits with black
above and below. Another, V4w.enko's *Perfect Everything*, is an ever-shifting pattern of
concentric colored rings that fills the whole panel and drifts on its own. The same artist's *Perfect Circles* is a companion series, slowly shifting concentric circles that fill the panel and drift on their own. And Cinzia y Gabriel's *Pendulum* is a
generative study of motion: a chain of colored orbs swings like a pendulum, tracing slow, ever-shifting arcs across the
whole panel. And Jeremy Booth's *Lost in Moffat County* is a series of painterly Western scenes that shift from day to
night on their own with your local time; switch on Animate for that piece (in Settings) to reveal a hand-drawn animated
easter egg. If you added this piece before, remove it and add it again: the newer copy loads faster, so it comes up
sooner when the rotation reaches it. And Chaz Wesley's *The Bloom* is a hand-drawn flower garden that blooms at sunset, with a little
spaceship drifting through the sky above it. It's the one piece that comes with its own music, and the
garden moves to it: the flowers and the sunset shift along with the song. A **Music** setting (in
Settings) starts **on**; turn it off and the garden keeps drifting on its own, silently. If you added
this piece before, remove it and add it again to get the music, since that's what downloads the song. And NFTman76's *Binary Mountains* is a glowing wireframe
mountain range under a starry sky, with snow drifting down as the view slowly circles it; a **Snow**
setting (in Settings) lets you choose how heavy the snowfall is, from Light Snow to a full Blizzard.
And Erick Calderon (Snowfro)'s *Chromie Squiggle* is the original Art Blocks artwork: a bright,
ribbon-like squiggle of shifting colors on a clean white background. A speed slider (in Settings) sets how
fast its colors flow, starting at the original's gentle pace, turned up to lively, or held still; you can
switch its background between **White** (the original) and **Black**; and on its card you can choose
**Fit** to show the whole squiggle or **Fill** to enlarge it to fill the screen, trimming the edges.
And Rich Caldwell's *Tiles* is a sweeping aerial photograph of the planet from above, sliced into a grid
of squares that shuffle themselves into a new arrangement every few seconds and then settle back into the
whole picture; a **Display** setting (in Settings) lets you choose **Static**, which simply holds the full high-resolution photograph
still, or the shuffling **Tiled** version. Tiled comes in **Low**, **Medium**, and **High** quality so you can
match it to your display. It starts on **Low**, which shuffles smoothly on any display; on a powerful display
(like a Mac) you can raise it to Medium or High for a sharper picture.
And Aluan Wang's *inkField* is a generative ink painting that draws itself onto paper, stroke by stroke, over a
minute or two, then starts a fresh one and keeps going. Each piece composes differently, some tall, some square,
and a tall one sits centered with black to either side. There's nothing to adjust, it just plays; because it paints
slowly, you may want to **Pin** it (or give the Rotation a longer time per piece) so you can watch a whole painting form.
And Jimena Buena Vida's *Conservation of Energy* is a series of animated pieces, each one stored entirely on the
blockchain and moving through a ten-second loop that never shows a seam. Each piece comes in three versions
Jimena built into it: landscape, portrait and square. An **Aspect Ratio** setting (in Settings) picks one. It starts on
**Auto**, which matches your screen: square on a square frame, landscape on a widescreen Mac. Any other shape
leaves black bars at the edges. Choose **Landscape**, **Portrait** or **Square** to show that version everywhere.
And nicedayjules's *Birds, Marfa* is an ink drawing of birds perched along barbed-wire fence lines, printed like
a silkscreen on paper that shimmers ever so slightly. The birds belong to a companion collection: whichever ones
are out of their homes when you add the piece are the ones that visit, and they keep flying in, preening and
flying off again on their own. Like *send/receive*, it goes online once, when you add it, and from then on shows
the flock as it was that day; remove it and add it again whenever you want to see who's visiting now. It's a tall
picture, so on a square frame or a widescreen Mac it sits centered with black to either side.
And Nygilia's *Starlight*, inspired by the Marfa Lights, is a series of still pictures drawn by code: three hundred
little glowing desert spirits scattered across the screen, in a palette that's different for every piece. It doesn't
move. The code draws it fresh to fit your screen and fills it edge to edge, so the tall original is trimmed: a square
frame shows its middle, and a widescreen Mac a band across it.
And Jen Stark's *Vortex* is a sculptural tunnel of rippling, hand-cut layers in bright bands of color,
grown from her signature paper sculptures: a hypnotic spiral that turns slowly all on its own, with some
pieces shifting their colors as they go. Every piece is square, so it fills the whole frame edge to edge,
always drawn fresh at your screen's full sharpness. There's nothing to adjust; it just plays.
And Graffiti On Grave's *She Never Let Go* is a tender scene drawn like an old comic print: a girl in red
stands alone in a wide pale field, holding a bright bundle of red balloons, one for every collector who
took an edition home before the sale closed, forty-eight in all. The balloons stir gently on their strings.
It's a widescreen piece, so it shows with black above and below; on its card you can choose **Fit** to
show the whole scene or **Fill** to enlarge it to fill the screen, trimming the sides.
The supported collections live in the **Settings** tab, under
**Connected Collections**, where you can hide ones you don't own and, for collections that have something to
adjust, turn their motion on or off, set sliders like speed or size, or choose a setting like the corner effect, snowfall, a Tiled/Static display, or an aspect ratio. This is new and **curated**: only collections that have been
specifically added will work, so it won't read just any link yet.

**Folder Collections** *(in the **Settings** tab)*. Have a whole folder of art on your computer, say
hundreds of clips, that you'd rather not upload one at a time? A **Folder Collection** points OpenObject
straight at that folder and plays it in place. *(Works whether a **computer** is your display or the **XXL frame** is, with the frame reading the
folder from your Mac over the network. The frame has a couple of extra needs, noted under "On the
frame" below.)*

- **Set one up:** Settings, **Folder Collections**, **Add folder**, then pick the folder in the dialog
  that opens. OpenObject counts the compatible files in it (the same image and video types as uploads;
  anything else is ignored). Click the name to give it a **name** and optional **artist**, and choose
  **Fit or Fill** for the whole folder. *(Order, **Sequence or Shuffle**, is set on the **Rotation** tab
  along with the timing, so it applies to whatever is playing.)* Nothing is copied; the files play
  right where they are.
- **Show it:** on the **Rotation** tab, use the **Source** dropdown to switch from **Library** to your
  folder. Your Library rotation pauses and the folder plays instead; switch back to **Library** any time
  and your rotation returns exactly as you left it. Only one source shows at a time.
- **It stays current:** add or remove files in the folder and OpenObject picks up the change on its own,
  no re-adding. Click a folder's **piece count** to open it and see what's inside.

Folders you save are remembered, so you can switch between them (and back to your Library) from the
Source dropdown any time.

**On the frame.** Your folders are set up on your Mac, but the frame can play them over your home
network. Set the folder up on the Mac as above, then on the **frame's** control panel open the
**Rotation** tab and pick the folder from the **Source** dropdown, exactly as you would on the Mac. The
frame quietly copies the art across as it plays, so it stays smooth, and clears that copy whenever you
restart it.

Three things the frame needs from your Mac:

- **Keep OpenObject open on the Mac.** The frame reads the folder from the app, so if the app is closed
  the folder can't show. If the frame can't find your Mac, it says so and tells you to open the app.
- **Don't let the Mac fully sleep while it's serving.** The screen going dark is fine, the Mac keeps
  serving; only a full sleep stops it. To leave a folder playing unattended, turn on **"Prevent
  automatic sleeping when the display is off"** in your Mac's energy settings. *(Once the frame has the
  art cached it plays on its own, so a Mac that nods off won't blank the frame; it just can't refresh
  until the Mac is back.)*
- **Keep OpenObject updated on the Mac.** If the frame finds a Mac running an older version, it'll tell
  you a newer one is available, update the app on the Mac.

There's also a **Help** card at the bottom of the **Settings** tab that walks through these folder steps
in the app, worded for whichever device you're reading it on (a frame or your Mac).

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

The **Sleep Schedule**, **Connected Collections**, **Folder Collections**, **Power**, **Password**,
**Network**, and **Help** sections **start collapsed** to keep the Settings tab short. Tap a header to
open one, and it stays the way you leave it.

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

**About** *(Settings tab, at the bottom)*. A small card with the OpenObject name, the version you're
running, a link to the project home at openobject.io, a link to the source code on GitHub, and the
license. The version shows here whether or not the Software Update card is present, so it's always
easy to find. If you ever inherit this frame and want to understand or rebuild what it runs, that
source link is where to start.

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

**Watch on an Apple TV, iPad, or iPhone (optional).** Your frame is a **Host**: it holds your art and
runs the control panel. The **Apple TV, iPad and iPhone** app ([on the App
Store](https://apps.apple.com/app/id6797132025), one app for all three) is a display that plays from a
Host on the same network, so it can show the frame's rotation on your TV or your iPad as well. Install
it, open it, and pick your frame from the list it finds. Connected Collections play on the iPad and
iPhone while the frame is on the network (not on the Apple TV, which has no way to run them), and they
keep playing on the frame either way. The iPad and iPhone app also keeps a **local copy** of the rotation
on the device, so it keeps playing with the frame asleep, or away from your network entirely, Connected
Collections included. See [the app section in the Mac guide](MAC-DISPLAY-SETUP.md#watch-on-an-apple-tv-ipad-or-iphone-optional)
for the details, including the local copy, which are the same whichever Host you use.

---

## Replacing the mini PC (advanced)

The computer on the back of the XXL can be swapped for a faster one of the same size, and this
section is the record of doing exactly that. It was done because some generative pieces ran choppy
on the original **MeLE Quieter 3Q**: that computer's one slow core, not its graphics chip, was the
limit, so only a faster core helps. The **MeLE Quieter 4C** (Intel N150) is the one MeLE box in
the identical case, and on the wall it made the same pieces smooth. The full step-by-step log,
with every command and every surprise, is **[the Quieter 4C migration runbook](QUIETER-4C-MIGRATION.md)**;
this is the shape of it.

**What you need.** The exact items that did the job:

- **MeLE Quieter 4C**, Intel N150, 16 GB, 512 GB SSD (Amazon listing B0DZGRLFLQ). It ships with
  Windows, which the install wipes, and with its own 12 V power adapter, used only on the desk.
- **One short HDMI cable with an angled plug at each end:** Alvin's Cables ultra-thin 8K HDMI 2.1,
  left-to-left angle, 30 cm (Amazon B0DQL5S49L). Why a cable at all is explained below.
- The **K400 Plus** keyboard and a **USB-A flash drive**, as in the list at the top.
- Any **monitor with an HDMI input** and a cable, borrowed for an afternoon.

**Two paths.** They differ only by a backup before and a restore after:

- **Your frame already runs OpenObject.** First, back up its data folder to your computer over
  SSH (the runbook has the one line; it is about 600 MB and takes under a minute). Then install
  on a desk as below. Then restore the backup onto the new unit, and only then open the frame. Your
  library, settings, sleep schedule and rotation all come across; the new unit even keeps the
  frame's identity, so the Apple TV and iPad apps recognize it.
- **Your frame does not run OpenObject yet.** Follow "Installing OpenObject" above with the new
  unit instead of the old one, on a desk or in the frame as you prefer, with the 4C notes in step 2.
  There is nothing to back up or restore.

**Install on a desk, not in the frame.** Plug the new unit into the borrowed monitor with the
keyboard receiver and the flash drive in its side ports, do the BIOS settings from step 2 above,
and run the install. The old unit keeps playing on the wall meanwhile, and the frame stays closed
until the new one is proven. One thing to expect that the original install never showed: early on,
Debian's installer says some hardware needs firmware files and lists a dozen `iwlwifi` names.
Answer **No** and carry on; the Wi-Fi works anyway. Pick the **BIWIN 512 GB** drive to wipe, not
the flash drive. When the screen reads `openobject login:` the install is done.

**The swap.** Unplug the frame's cord and lay it face down on something soft. The mini PC hangs
on a bracket by two screw heads. Slide the old unit up, unplug its three leads (the keyboard
cable if it has one, the HDMI, and the black USB-C power lead), and set it aside untouched. Then,
before mounting anything, plug the power lead into the new unit's power port, the USB-C beside
the Ethernet jack, and plug the cord in for a moment: the new unit should light up by itself.
Unplug again, slide the new unit into the bracket, and reconnect.

**Why the HDMI cable.** On the original unit a short rigid coupler joined the frame's HDMI
connector straight into the mini PC's HDMI 1, which lines up with it. The 4C's mounting holes
sit a quarter inch lower, so hung on the same bracket it no longer lines up and the coupler falls
short. The answer is the 4C's **HDMI 2**, which sits beside the frame's connector rather than
under it, joined by the short double-angled cable above. Four cables were tried; that one lay
best in the 1 3/16 inch gap. Nothing in the software cares which HDMI port is used.

**Finishing.** Leave the keyboard's receiver in a side port so a wireless keyboard can always
reach the frame. Plug the cord in: the new unit starts by itself and shows the MeLE logo instead
of the Infinite Objects one, which is normal, and the art follows. Open `http://openobject.local`
to confirm the control panel. If you connect by SSH from a computer that knew the old unit, it will
refuse at first because the name now belongs to a different machine; `ssh-keygen -R openobject.local`
clears the old entry.

**Keep the old unit.** It is not changed by any of this. If anything about the new one
disappoints, it slides back in with its own leads and plays as before.

---

## If the frame needs a different Wi-Fi network

You set the frame's Wi-Fi once, while installing it. If that network ever changes, because you
replaced your router, changed its password, or moved the frame to a different building, the frame
will ask you for the new details itself. You don't need a keyboard or a cable.

**What you'll see.** After a few minutes of not finding its network, the frame stops showing art and
puts up a **Connect to Wi-Fi** screen with a network name and a password on it.

**What to do, from a phone:**

1. In your phone's Wi-Fi settings, join the network shown on the frame: **OpenObject-Setup**, with
   the password **openobject**. *(It can take a minute or two before your phone lists it. That's your
   phone deciding when to look for new networks, not the frame. Give it a moment.)*
2. Your phone may warn that this network has no internet. That's expected, and fine. Stay on it.
3. Open **openobject.local** in your browser. (If that doesn't load, use **192.168.4.1** instead.)
4. Choose your Wi-Fi network from the list, type its password, and tap **Connect**.
5. Watch the frame. When it joins your network, it goes straight back to showing your art. That's
   your confirmation. Your phone will drop off the frame's setup network at the same moment, so
   you'll need to re-join your home Wi-Fi on the phone if it doesn't do it for you.

**If your network isn't in the list** (some are set up not to broadcast their name), tap
**Enter a network name instead** and type it exactly.

**If you'd rather not deal with it right now**, tap **Show art now, set up later** at the bottom of
that page. Your art comes back on the frame immediately. The frame keeps offering its
**OpenObject-Setup** network the whole time, so you can pick this up whenever you like: join that
network again from your phone, return to the same page, and finish. Nothing you skipped is lost, and
the art never has to stop for it.

Two things to know about doing it later. The frame goes back to looking completely normal, so there
is nothing on the wall reminding you it isn't on your Wi-Fi (your art plays from the frame itself,
which is why it doesn't need one). And if the frame is unplugged and plugged back in, it puts the
**Connect to Wi-Fi** screen up again, on the assumption that a fresh start is a good moment to
mention it. Tap **Show art now, set up later** again if you're still not ready.

While you're waiting to get to it, anything that needs the network is unavailable: the control panel
won't load from your phone or computer, a folder shared from your Mac won't play, and Connected
Collections can't fetch. Art already on the frame plays exactly as usual.

**A few things worth knowing:**

- The frame waits about **five minutes** before offering this, so a router rebooting or a brief
  internet hiccup never interrupts your art.
- While that screen is up, the frame steps away every few minutes to see whether your usual network
  has come back. If it has, the frame simply returns to your art with nothing for you to do. (It
  won't do that while your phone is connected to it, so it can't interrupt you mid-setup.)
- The frame **remembers every network it has used**. If you take it back somewhere it has been
  before, it reconnects by itself.

---

## If something seems stuck

- The frame restarts itself whenever it gets power, so a quick **power cycle at the outlet** (or a
  smart plug) fixes most hiccups.
- For normal restarts, use the **Restart** button in the control panel.
- If the control panel won't load, re-check that your device is on the same Wi-Fi as the frame, and
  try the **IP address** shown in the control panel instead of `openobject.local`.
- If the frame ever **drops off Wi-Fi** (the art is still on screen but the control panel won't load
  from any device), it now keeps its Wi-Fi awake to prevent this, and if it still happens it
  **re-joins on its own in a minute or two**, so give it a moment before reaching for the power. A
  power cycle still fixes it right away if you're in a hurry. If it genuinely can't find your network
  at all, it will offer you the setup screen described above.
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

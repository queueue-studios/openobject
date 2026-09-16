# Set up OpenObject on your Mac

OpenObject turns your Mac and an everyday monitor into a borderless art display: your art, edge to edge, no browser bars or buttons. You control it from any browser on your network, on your phone or another computer. Nothing leaves your network, no account, no cloud.

A couple of things that are normal, so they do not surprise you:

- When the display first opens, you may see the OpenObject logo for a moment while the first piece loads.
- A piece can linger a little while the next loads quietly in the background, then they cross fade. This is on purpose, so you never see a blank or half-loaded screen.

## Before you start

- A Mac running macOS 15 (Sequoia) or later, and a monitor to display on (your Mac's own screen, or an external one).
- Google Chrome installed. OpenObject uses it behind the scenes to render the art full screen; you never open or use it as a browser. If you do not have it, it is free from google.com/chrome.

## Install

1. Download OpenObject from [the download page](https://github.com/queueue-studios/openobject/releases/latest) (or from openobject.io).
2. Open the downloaded **OpenObject.dmg**.
3. Drag **OpenObject** onto the **Applications** folder.
4. Open **Applications** and double-click **OpenObject**.

## First launch

The first time you open it, macOS asks about local network access, and may confirm the app once:

- If you see a prompt that OpenObject was **downloaded from the Internet** and asks if you're sure you want to open it, click **Open**. OpenObject is signed and notarized by Apple, so this is the routine one-time confirmation for a downloaded app, not a warning. (You won't see this if you built or copied it locally.)
- **"Allow "OpenObject" to find devices on local networks?"** Click **Allow**. This is how OpenObject serves the control panel to your phone and other devices, and finds a frame if you have one. The prompt's boilerplate about collecting data "from devices on your networks" is Apple's standard wording for this permission; OpenObject only uses it to reach your own devices on your own network, and nothing leaves it.

OpenObject opens a small window and starts running on your Mac.

## Add your art

1. In the OpenObject window, click **Open Control Panel**. Your browser opens the control panel.
2. Drag a few images or videos onto the upload area.
3. Set the order, how long each piece holds, Fit or Fill, and so on. You can do this now or later; the display updates on its own.

You can open the control panel from any device on your network, not just this Mac.

## Show it on your screen

Click **Open Display**. Your monitor fills edge to edge with your art, no bars or buttons. That is your display.

## Getting around

Once the display is full screen, the OpenObject window is hidden behind it. Your remote is the **OpenObject icon in the menu bar** (the small square at the top-right; move your mouse to the very top of the screen to reveal the menu bar over the art):

- **Return to Display** jumps back to the full-screen art.
- **Show OpenObject** brings the window forward (to open the control panel, or stop the display).
- **Stop Display** closes the full-screen display.

## Auto Display: art when you step away

OpenObject can put your art on screen by itself after a stretch of no typing or mouse movement, then get out of the way the moment you come back. It works like a screen saver, though it is not one.

In the **OpenObject** app menu choose **Settings** (or press Command-comma), and set **Auto Display** to how long your Mac should sit idle first. It is **Never** by default, so nothing changes until you pick a time.

Once it is on: step away, and after your chosen time the art fills the screen exactly as if you had clicked Open Display. Touch the keyboard or trackpad and your desktop comes straight back, with everything where you left it. If you have more than one screen, the art plays on **all** of them, with a different piece on each, the way a screen saver does.

A few things worth knowing:

- **Important: your Mac will not lock on its own while the art is showing.** Your Mac locks once its display turns off, and the art keeps the display on. If you want your Mac locked while you are away, press Control-Command-Q before you go, or leave Auto Display set to **Never**.
- **Pick a time shorter than your screen's own sleep setting.** Your Mac turns its display off after a while on its own (System Settings > Lock Screen, "Turn display off when inactive"). If Auto Display is set to wait longer than that, your screen goes dark before the art ever starts. OpenObject warns you in Settings if the time you picked has this problem.
- **Your Mac's screen saver does not need changing.** OpenObject's art stays up regardless of it.
- **Plugging a screen in or out stops the art.** That is deliberate, since it means you are back at your Mac. Leave it alone again and the art returns after your chosen time.

While the art is showing, your Mac stays awake. Set Auto Display back to **Never** and it goes back to sleeping and blanking exactly as it always did.

## Connected Collections

Alongside your own uploads, OpenObject includes a small, hand-picked shelf of **Connected Collections** (in the control panel's Settings). These are not standard images or videos, but generative and interactive art that runs as live code (p5.js sketches, or interactive HTML), rendered right on your screen. They are selectively curated from the personal collection of OpenObject's developers, so they play out of the box. It is a curated shelf, not a general NFT reader.

## Watch on an Apple TV, iPad, or iPhone (optional)

Your Mac is a complete OpenObject setup on its own. These apps are extra screens for the art you
already have; they are not required and they do not replace anything.

The Mac (or a frame) is the **Host**: it holds your art and runs the control panel. The Apple TV and
iPad apps are **displays**, playing from a Host already running on your network. So the Mac app needs
to be open, on the same Wi-Fi, for them to find it.

**Apple TV.** [Available on the App Store](https://apps.apple.com/app/id6797132025). Install it,
open it, and pick your Mac from the list of Hosts it finds. Your art plays on the TV, following the
same rotation, timing, and settings you already set from the control panel. There is nothing to
configure on the TV itself.

**iPad and iPhone.** [Available on the App Store](https://apps.apple.com/app/id6797132025), the
same app as the Apple TV one. Install it, open it, and pick your Mac the same way. The art plays full
screen, following the rotation and settings you set from the control panel.

**Taking the art with you (iPad and iPhone).** The iPad and iPhone app keeps a **local copy** of the
rotation it is showing, on the device itself, so it keeps playing with the Mac asleep, and away from your
network entirely: load it at home, carry it to a gallery, and play with no Wi-Fi at all. There is nothing
to turn on. Leave the app on the art for a few minutes while the Mac is running; tap the art once and the
status in the top corner tells you where it stands, **Saving local copy** with a count while it fills,
then **Local copy ready**. After that, opening the app anywhere plays the art straight away. When the Mac
is not answering, the same corner reads **Playing local copy**, which is also why changes you make on the
Mac will not appear until the device sees it again. In the Host list, a Host that is not on the network
but whose art is on the device shows with a **Local copy** tag; tap it to play. While it is playing the
copy, tapping **Playing local copy** opens two settings you can change on the spot, **Order** (Sequence or
Shuffle) and **Every** (how long each piece stays); a change made this way lasts until the device sees the
Mac again, when the Mac's own settings take over. The copy follows your
rotation: a piece you take out of the rotation leaves the device a day later, and choosing a different
Host replaces the copy with that Host's. It uses as much space as the rotation needs, never past a
reserve it leaves free for the rest of the device (a tenth of its storage); if a rotation will not all
fit, the corner says how many pieces did. To remove the copy entirely, delete the app from the device
(Settings > General > iPad Storage, or iPhone Storage, then OpenObject and Delete App).

**What plays on them.** Your uploaded images and video, and Folder Collections, all exactly as on
your Mac. **Connected Collections play on the iPad and iPhone** while the Mac is on the network: the
pieces are small web programs, and the app runs them from the Mac as they come up, so they are not part
of the local copy yet. **They do not play on the Apple TV**, which has no way to run them. They keep
playing on your Mac and on a frame either way.

**The Apple TV stores no art.** It reads from the Host as it plays, so it needs the Mac running: turn
the Mac off and the TV has nothing to show; turn it back on and the art returns. The iPad and iPhone keep
the local copy described above, so they carry on without the Mac.

---

## Everyday use

- Leave OpenObject and the display running; it keeps playing on its own.
- Change your art anytime from the control panel, on any device. The display updates within a few seconds, no restart.
- To rest the screen overnight or while away, set a **Sleep Schedule** in Settings.

## Keeping it updated

In the **OpenObject** app menu, choose **Check for Updates**; if there is a newer version, it downloads and installs it.

## If something is not right

- **Open Display does nothing, or asks for Chrome.** OpenObject needs Google Chrome installed. Install it from google.com/chrome and try again.
- **The display only shows the OpenObject logo.** That is the idle screen when nothing is in the rotation yet, or the first piece is still loading. Add art, or give it a moment.
- **You cannot find the window.** Click the OpenObject icon in the menu bar and choose **Show OpenObject**.

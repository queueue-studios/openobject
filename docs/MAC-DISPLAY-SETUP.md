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

## Connected Collections

Alongside your own uploads, OpenObject includes a small, hand-picked shelf of **Connected Collections** (in the control panel's Settings). These are not standard images or videos, but generative and interactive art that runs as live code (p5.js sketches, or interactive HTML), rendered right on your screen. They are selectively curated from the personal collection of OpenObject's developers, so they play out of the box. It is a curated shelf, not a general NFT reader.

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

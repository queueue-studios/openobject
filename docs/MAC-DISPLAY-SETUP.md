# No Frame? Use Your Mac as the Display

OpenObject was not only designed to run on an Infinite Objects XXL frame. You do NOT need the XXL or even a square screen to use it. This guide turns a Mac into the art display itself: a clean, full screen player with no browser bars or buttons, on your own monitor.

*(If you do have an Infinite Objects XXL frame, follow the frame setup guide instead.)*

You will use the Terminal app for a few copy and paste commands. Just paste each one and press Return.

A few things that are normal, so they do not surprise you:

- When the display first opens, you may see the OpenObject logo for a moment while the first piece loads.
- A piece can linger a little while the next one loads quietly in the background, then they cross fade. This is on purpose, so you never see a blank or half loaded screen.

## Before you start

Install two free apps if you do not already have them:

1. **Node** (the engine that runs OpenObject)
   - Go to **nodejs.org**.
   - Click **Get Node.js**, then choose **macOS Installer (.pkg)**.
   - Open the downloaded file and click through the installer (Continue, Agree, Install, then your Mac password).
2. **Google Chrome**
   - If it is not already installed, get it from **google.com/chrome**. (Most people already have it.)

## Step 1: Download OpenObject

1. Go to the OpenObject page on GitHub: **https://github.com/queueue-studios/openobject**
2. Click the green **Code** button. It is the green button on the right, just above the list of files. (Do not use the "Code" tab near the top of the page, which is a different thing.) Then choose **Download ZIP**.
3. Open your **Downloads** folder and double click the ZIP. It unzips into a folder named **openobject-main**.

## Step 2: Put it in your home folder

Open **Terminal** (press Cmd and Space, type Terminal, press Return). Paste this line and press Return:

```
mv ~/Downloads/openobject-main ~/OpenObject
```

That moves the folder out of Downloads into your home folder and renames it to **OpenObject**, in one step. Nothing is copied or changed inside, just moved and renamed.

## Step 3: Start OpenObject

In the same Terminal window, paste these one at a time, pressing Return after each.

```
cd ~/OpenObject/player
```

```
npm install
```

Wait about fifteen seconds for it to finish. You will likely see a note like "1 high severity vulnerability." That is normal npm housekeeping and safe to ignore for a setup like this, because OpenObject runs only on your own machine and is never exposed to the public internet. Do not run `npm audit fix`.

```
npm start
```

You will see a line saying it is running. **Leave this Terminal window open.** This is your server that presents the art to your Mac's monitor.

## Step 4: Add your art

1. Open **Safari** and go to **http://localhost:3000**. This is your control panel. (Use Safari here, not Chrome, so Chrome stays free for the next step.)
2. Drag a few images or videos onto the upload area.
3. Arrange them however you like.

You can click **Open display** at any time for a quick look in a normal browser tab. Reminder: you will have periods of initial load time before art displays.

## Step 5: Go full screen

1. **Quit Google Chrome completely** if it is open (Cmd and Q). It also helps to close other browser windows.
2. With Terminal open, go to the **Shell** menu in the macOS menu bar at the top of the screen and choose **New Window**. This second window lets you run the next command while the first window keeps the server running.
3. Paste this and press Return:

```
open -a "Google Chrome" --args --kiosk "http://localhost:3000/display"
```

Chrome fills the whole screen with your art, no bars or buttons. That is your display. Art rotation follows the settings you control in the OpenObject control panel.

If it opens a normal Chrome window instead of full screen, Chrome was still running. Quit it completely (Cmd and Q) and run the command again. If it still will not go full screen, use this version instead, which works even when Chrome is open:

```
open -na "Google Chrome" --args --user-data-dir="/tmp/oo-kiosk" --kiosk "http://localhost:3000/display"
```

## Turning the display on and off

- **Exit full screen:** press **Cmd and Q**.
- **Go back to full screen:** run the command from Step 5 again.
- **Change your art:** open the control panel in Safari (http://localhost:3000), make your changes, and the display updates on its own within a few seconds. No need to restart it.
- **Stop OpenObject entirely:** go to the Terminal window running the server and press **Control and C**, or just close the window.

## If something is not right

- **The display only shows the OpenObject logo.** The server may not be running. Check that the Terminal window from Step 3 is still open and shows it running. If not, run `npm start` again.
- **The command opened a normal browser window.** Chrome was already running. Quit it completely and try again, or use the "works even when Chrome is open" command above.
- **`npm install` showed a vulnerability warning.** That is normal (see Step 3). Safe to ignore.

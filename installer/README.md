# installer/: turn a MeLE into an OpenObject frame

This provisions a **minimal Debian** install into an OpenObject appliance: it boots with no
desktop straight into **Chromium (kiosk) on `/display`**, reachable at
**`http://openobject.local`**. On the device, **systemd** runs the player and the kiosk.

It is a hands-on install: run the standard Debian installer, then this script (not a single
flashable image).

```
installer/
├─ install.sh                     # idempotent provisioner, run once on minimal Debian
├─ systemd/
│  ├─ openobject-player.service   # Node player on :80 (systemd = the supervisor)
│  └─ openobject-kiosk.service    # cage + Chromium kiosk on tty1
└─ kiosk/
   ├─ start-kiosk.sh              # waits for /healthz, then launches cage
   └─ chromium-kiosk.sh           # Chromium kiosk flags → http://localhost/display
```

## How it works

- **`cage`** (a tiny Wayland *kiosk compositor*) runs one fullscreen app and nothing else, no
  desktop, no window manager, cursor hidden, no screen blanking. It launches **Chromium** in
  `--kiosk` pointed at the local `/display` page.
- **systemd** is the device's supervisor. `openobject-player.service` runs `node server.js`
  with `OO_SUPERVISED=1` and `Restart=always`; the player **exits with code 75** to request a
  relaunch (after a self-update or the **Restart** button), and systemd brings it back.
- **Runtime data** (library, uploads, browser profile) lives under **`/var/lib/openobject/`**,
  outside the code checkout at **`/opt/openobject`**, so self-update and re-seeding never risk
  the art (HANDOFF §8, §15).
- **Port 80** via a single Linux capability (`CAP_NET_BIND_SERVICE`), so the panel is plain
  `http://openobject.local` with no port. **Avahi** advertises that name.

---

## Bench procedure

> Working model: drive the frame by hand at its keyboard (no SSH). Network is **Wi-Fi-only**,
> you'll type the Wi-Fi name + password once during the Debian install.

### 0. Capture hardware facts first (before wiping anything)

From the **Ubuntu live USB** (Try Ubuntu), open a Terminal and record:

```
lspci -nnk | sed -n '/Network controller/,/^$/p'   # the Wi-Fi chip + its kernel driver (HANDOFF §19)
lspci -nnk | grep -iA3 vga                          # the iGPU + driver
```

If a phone photo of those is easier, that's fine, we just need the Wi-Fi `[vvvv:dddd]` id, its
`Kernel driver in use:` line, and the `Subsystem:` name.

### 1. Make the seed (on the Mac, in this repo)

The frame's checkout is seeded from a **git bundle**, one file, history intact (so self-update
keeps working), no runtime art. Plug in any USB stick (or use the backup drive) and run:

```
git bundle create /Volumes/<STICK>/openobject.bundle --all
```

> **Seed-stick format:** it must be readable by *both* macOS and the frame's Linux, so format it
> **MS-DOS (FAT)** or **exFAT**, not a Mac-only format (APFS / Mac OS Extended). Most sticks
> already are FAT/exFAT out of the box; only reformat if yours is Mac-only. In **Disk Utility**:
> *View → Show All Devices*, select the **stick** (check the size so it isn't your Mac or the
> backup drive!), **Erase** → Format **MS-DOS (FAT)** (or **ExFAT** for a stick over 32 GB),
> Scheme **Master Boot Record**.

### 2. Install minimal Debian on the eMMC

1. On the Mac, flash the **Debian stable netinst** ISO to a USB stick. **No need to format this
   stick first**, the flasher overwrites it whole. Use **balenaEtcher** (pick the ISO, pick the
   stick, Flash, it hides your system disk so you can't mis-target it) or, for builders, `dd`
   (verify the target disk first).
2. Boot the MeLE: tap **`Del`** for BIOS or use **Boot Override → `UEFI: <stick>`**.
3. Run the installer. **Wipe `/dev/mmcblk0`** (guided, entire disk). Choose a **minimal**
   system, at *Software selection* untick everything **except "standard system utilities"**
   (no desktop). Set the **hostname to `openobject`**, and **join your Wi-Fi** when asked.
4. Reboot into the new Debian and log in at the console.

### 3. Run the installer

Mount the seed stick, drop the checkout into place, and provision:

```
sudo apt update && sudo apt install -y git
sudo mkdir -p /mnt/seed && sudo mount /dev/sdX1 /mnt/seed      # your stick's partition
sudo git clone /mnt/seed/openobject.bundle /opt/openobject
sudo bash /opt/openobject/installer/install.sh
sudo reboot
```

`install.sh` is **idempotent**, if a step fails (e.g. network hiccup), fix it and run it again.

### 4. Verify on the panel

- The panel shows the **OpenObject screen** edge-to-edge (the branded idle screen until art is
  added), no desktop, no cursor, no chrome.
- From a phone on the **same Wi-Fi**, open **`http://openobject.local`** → the control panel.
- **Upload** an image/clip → it appears in the Library and starts playing in the rotation.
- **Settings → Restart** → the panel blinks and comes back (systemd relaunched the player).
- **Unplug and replug power** → the frame auto-boots straight back to `/display`.

---

## Configuration knobs

`install.sh` reads these env vars (sensible defaults otherwise):

| Var | Default | Purpose |
|---|---|---|
| `OO_TARGET` | `/opt/openobject` | where the checkout is provisioned |
| `OO_DATA_ROOT` | `/var/lib/openobject` | runtime data (never overwritten) |
| `OO_ORIGIN` | the GitHub HTTPS URL | git remote for self-update |
| `OO_WIFI_SSID` / `OO_WIFI_PSK` | (auto-detected, else prompts) | Wi-Fi for the NetworkManager handoff |

Chromium one-off flags (no file edit needed) via the kiosk service environment, e.g.
`OO_CHROMIUM_EXTRA_FLAGS="--disable-gpu"`.

## Notes & fallbacks

- **Self-update:** origin points at the public GitHub repo, so *Check for updates* fetches
  `origin/main` and fast-forwards. (`GIT_TERMINAL_PROMPT=0` keeps any auth hiccup failing fast
  rather than hanging.)
- **Wi-Fi firmware:** Debian 12.4+ netinst bundles non-free firmware, so the onboard Wi-Fi
  should work in the installer. If not, a known-good USB Wi-Fi dongle is the documented fallback
  (HANDOFF §3); capture the chip id in step 0 so we can name the exact firmware package.
- **Kiosk fallback (X11):** if `cage` misbehaves on this iGPU, the X11 path is
  `apt install -y xserver-xorg xinit openbox unclutter`, then run Chromium under `startx` with
  `--ozone-platform=x11` (drop `--ozone-platform=wayland`). The `chromium-kiosk.sh` flags are
  otherwise identical.

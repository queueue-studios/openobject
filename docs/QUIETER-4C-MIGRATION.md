# Moving the XXL from the Quieter 3Q to a Quieter 4C

A runbook for replacing the frame's mini PC with a faster one in the same shell, written
before the hardware arrived so the work can start cold. It records why, what was bought, how
the back of the frame is laid out, the bench procedure, the swap, and the rollback. Append to
the decision log at the bottom as steps actually happen.

Related: HANDOFF §2 (the hardware record), `installer/README.md` (the install runbook this
one leans on), `SETUP-GUIDE.md` (the owner-facing install), `appendix-backup-original.md`.

---

## 1. Why

On 2026-10-31 the frame was measured while Jimena Buena Vida's *Conservation of Energy*
(token CoE #03, a 2D-canvas p5 page at 1920 x 1920, 30 frames per second) played and looked
choppy. The findings, each read from the running frame:

- Chromium 151 reports the 2D canvas, rasterization, compositing and WebGL all enabled on the
  GPU, through ANGLE on Mesa's Intel driver (Skia backend GaneshGL). No software fallback.
- Even so, the main thread of Chromium's GPU process held one CPU core at 100 percent for as
  long as the piece played, while the Intel GPU sat at its 200 MHz floor and about 20 percent
  busy by the kernel's per-process render counter. The piece's own script took another 20
  percent of a second core. The other two cores were near idle.
- All four cores held 2.8 GHz against a 2.9 GHz ceiling, turbo on, the stock 8 W power limit,
  zero thermal throttle events. Package temperature 85 to 89 C, 14 degrees under the first
  trip point.

So the piece is bound on single-thread CPU work per drawn shape (Skia preparing geometry for
the GPU plus driver overhead), not on the GPU and not on heat or power. Lowering a piece's
quality cuts pixels, not shapes, which is why it stayed choppy. No Chromium flag changes this
picture. A faster single core is the one thing that maps onto the bottleneck.

The earlier tempo fix (HANDOFF §20, 2026-10, CoE's injected clock) was a workaround for the
same symptom: the frame cannot draw this family of pieces at 30 frames per second.

**Expected result.** The N150 is roughly 30 to 40 percent faster per thread than the N5105.
On this bottleneck that translates almost directly: smoother, not transformed. A piece at 12
frames per second today should land around 16 or 17. Judge the swap by that, not by 30.

## 2. What was bought (2026-10-31, Amazon)

| Part | Detail | Replaces |
|---|---|---|
| MeLE Quieter 4C, Intel N150 (2025 revision) | 16 GB DDR4 (single slot), 512 GB M.2 NVMe SSD, Wi-Fi 5 (802.11ac) + BT 5.1, Realtek RTL8111H Gigabit Ethernet. Ships with Windows 11 Pro (wiped on the bench), a 12 V / 2 A USB-C adapter, a VESA plate. Two-year warranty, three-month replacement window. Listing B0DZGRLFLQ, about $300 | MeLE Quieter 3Q, N5105, 8 GB, 128 GB eMMC |
| CybNemo 90-degree USB-C male to USB-A 3.0 female cable, 30 cm, 2-pack (one left angle, one right) | 5 Gbps. Listing B0FR9KWQVW | CableCreation CC0516 left-angle USB-A extension, 1 ft |

Kept as is: the UGREEN 25946 4-port USB 3.0 hub (2 ft cord), the Logitech K400 Plus, the
Debian netinst USB stick.

Same shell to the millimeter: 131 x 81 x 18.3 mm, 203 g, so the bracket and the slide-in fit
are unchanged. MeLE sells the identical build direct in two grades (SE-Grade, Business-Grade)
at a much higher price; Amazon's unit is the same hardware.

## 3. The back of the frame

The mini PC sits below the panel's controller board with its port edge facing **up**, into a
gap of about one centimeter. Everything plugs in along that edge. The two screws on the bracket
directly above the mini PC retain captive nuts inside the chassis: **do not touch them**
(HANDOFF §4). Insert trick: slide the unit up to free the HDMI and USB-C, seat the plugs,
reseat, slide back down.

Port order along that edge, left to right as seen from behind the frame:

| Position | Quieter 3Q (today) | Quieter 4C | What plugs in |
|---|---|---|---|
| 1 | USB-A 3.0 | **USB-C** (data 10 Gbps, DisplayPort, PD in) | the angled extension, cable exiting to the right and looping down to the hub. On the 4C this is the new USB-C cable; USB-C is reversible, so flip the plug to choose the exit direction |
| 2 | 3.5 mm audio | 3.5 mm audio | nothing |
| 3 | microSD | microSD | nothing |
| 4, 5 | HDMI, HDMI | HDMI, HDMI | the controller's HDMI lead. In the 2026-11-05 photo it appears to sit in the **left** HDMI of the pair, the one nearer the USB-A end; confirm by eye before unplugging and use the same one on the 4C |
| 6 | (none) | CMOS reset pinhole | nothing |
| 7 | USB-C, power only | USB-C, power only (12 V / 2 A) | **the controller's black USB-C power lead**, just right of the HDMI pair in the photo. On the 4C this is the port beside Ethernet, not the new USB-C at position 1. First check when the frame is open: move this lead to the 4C's power port and see the 4C start, before the 3Q comes out of the bracket |
| 8 | Gigabit Ethernet | Gigabit Ethernet | nothing |

The right-hand side carries three USB-A ports on both units; they are not reachable when the
unit is mounted, which is why the hub hangs off position 1. The 3Q is powered over USB-C, not a
barrel jack, despite what HANDOFF §2's table says; every review of the 3Q and the photo of the
back agree, and the 4C's power port takes the same 12 V / 2 A over the same connector. The 4C's
own adapter is the fallback if the frame's lead and the new unit disagree.

## 4. Bench procedure

Everything up to §5 happens on a desk, with the frame untouched and the 3Q still playing art.
The frame is only opened once the 4C plays the library on a bench monitor.

**Needed on the desk, gathered before you start:**

- the 4C and the 12 V USB-C adapter from its box
- a monitor with an **HDMI** input, and an HDMI cable (borrow one from another workstation)
- a USB keyboard. The K400 is wireless to its receiver, but the receiver is a plain USB
  keyboard to the computer and works in the BIOS and the installer with no driver. Put the
  **new angled USB-C cable** in the 4C's left-end USB-C and the receiver on its USB-A end: that
  is the port and cable the frame will use, so the desk proves both before the frame is opened.
  The Debian stick goes in one of the three side USB-A ports
- the Debian 13 netinst USB stick. Flash a fresh one even if the June stick is at hand: its
  label cannot be read from a Mac without administrator rights, and balenaEtcher overwrites the
  whole stick anyway, so a fresh flash costs nothing and leaves a known, current installer.
  Done 2026-11-05: Etcher (the arm64 build on an Apple Silicon Mac), the
  `debian-13.7.0-amd64-netinst.iso` image (756 MB, amd64 because the 4C is an Intel PC whatever
  Mac downloads it), checksum matched Debian's `SHA256SUMS`, written to a 32 GB stick. Two
  things to expect: the main image server (`cdimage.debian.org`) was down that morning and a
  mirror such as `debian.osuosl.org` carries the same files, and macOS says a Debian stick is
  "not readable by this computer" both before and after flashing; click **Ignore**, never
  Initialize
- the Mac, on the same network, for the backup archive and the control panel checks

**Why a desk and not the frame.** The frame's panel would serve as the install monitor exactly
as it did in June. The desk is chosen so the 3Q keeps playing art and the frame stays closed
until the 4C has proven itself; a bad first attempt then costs nothing. An owner with no spare
monitor can do §4.3 to §4.5 inside the frame instead, at the cost of the wall going dark for the
session and of the 3Q coming out before the 4C is known good.

### 4.1 Back up the frame's data (before anything else)

The whole runtime state lives in `/var/lib/openobject`: `data/openobject.sqlite` with its `-wal`
and `-shm` side files (library rows, settings, the pin, the rotation), `data/collections/` (the
Connected mirrors), `uploads/` (the art files), and `chromium/` (the browser profile, which is
not backed up or restored). Every file under it is world-readable, so the login user can copy it
without sudo, and the whole thing streams to the Mac in one command with no staging file on the
frame. From the Mac, in Terminal.app, from any directory (the Claude desktop app has no Local
Network access on this Mac, so these lines are always pasted there by hand):

```
ssh mattlhx@openobject.local 'tar -C /var/lib --exclude=openobject/chromium -cf - openobject | gzip -1' > ~/Code/OpenObject/Backup/oo-backup-$(date +%Y%m%d).tgz; echo "exit $?"; tar -tzf ~/Code/OpenObject/Backup/oo-backup-$(date +%Y%m%d).tgz | wc -l; ls -lh ~/Code/OpenObject/Backup/oo-backup-$(date +%Y%m%d).tgz
```

`Backup/` is gitignored. A read-only preflight first (`du -sh /var/lib/openobject`, a `find
! -readable`, and `ls -l` of the SQLite files) tells you the size, that nothing needs sudo, and
whether the database is quiet: a `-wal` file untouched for days means no write is in flight, so
a live copy is consistent as long as all three SQLite files travel together. If the WAL is being
written as you copy, stop the player for the seconds the copy takes
(`sudo systemctl stop openobject-player`, copy, `start`); the wall shows the kiosk's error page
meanwhile. Then confirm the archive holds what the frame holds: `gzip -t`, the three SQLite
files, the upload count and the collection count against the preflight's numbers.

- [x] Preflight run 2026-11-05: 606 MB in all, 20 uploads, 18 Connected mirrors, nothing
      unreadable, WAL last written 2026-11-01, frame on OpenObject 1.10.0, root disk `mmcblk1p2`
      with 96 GB free
- [x] `oo-backup-20261105.tgz`: exit 0, 179 entries, 569 MB, gzip verified, the three SQLite
      files, 20 uploads and 18 collection directories all present

### 4.2 The 4C's hardware facts

The 3Q's install captured these from an Ubuntu live stick before wiping, because the original
software was worth keeping. The 4C ships with Windows, which is not, so the facts are captured
from the installed Debian instead (§4.4, before the OpenObject installer runs): the Wi-Fi chip
(`lspci -nnk | sed -n '/Network controller/,/^$/p'`), the iGPU (`lspci -nnk | grep -iA3 vga`),
and the drive (`lsblk`, expect `nvme0n1`, not `mmcblk`). An Intel Wi-Fi chip (`iwlwifi`) is the
no-work case; the Debian installer shows whether it sees the radio when it offers Wi-Fi networks.
A Realtek chip usually needs `firmware-realtek`, which the netinst carries. Record the
`[vvvv:dddd]` id either way; it goes into HANDOFF §2 for the new unit.

- [ ] Wi-Fi chip and driver recorded
- [ ] Drive name recorded

### 4.3 BIOS

`Del` at power-on. Set, and write each down as found:

- Secure Boot **off** (the 3Q had it off; Debian would also boot with it on).
- Boot mode UEFI.
- **Auto Power On** (also called Restore AC Power Loss or State After G3) set to **Power On**.
  MeLE lists the feature for the 4C. The 3Q's custom firmware had no toggle and simply booted on
  power return; the retail 4C's default is unknown, and the frame depends on this, since
  unplugging and replugging the cord is how it is booted and recovered.
- Leave power limits at stock. The 3Q held full clock at 8 W inside the enclosure; the 4C runs
  the same budget.

- [ ] Auto Power On confirmed by unplugging and replugging the adapter: the unit must start by itself

### 4.4 Install Debian and OpenObject

Follow `installer/README.md` steps 1 and 2 exactly as for the 3Q, with these differences:

- The target disk is the **NVMe SSD** (`nvme0n1`, about 477 GiB), not the eMMC. Guided, entire
  disk, one partition, as before.
- Hostname `openobject`, same as today. Two hosts with that name cannot share the Wi-Fi at
  once, so **keep the 4C on Ethernet or skip Wi-Fi during the bench phase**, or give it a
  temporary hostname and rename it (`hostnamectl set-hostname openobject`) right before the
  swap. Avahi follows the hostname.
- `install.sh` is unchanged. Its two hardware-specific lines are harmless here: `reboot=pci` is
  a generic Intel reset path, and the `iwlwifi power_save=0` modprobe option only applies if the
  Wi-Fi is Intel.

- [ ] Debian installed on the SSD, boots to the console
- [ ] `install.sh` run, reboots into the OpenObject idle screen on the bench monitor

### 4.5 Restore the data

With the player and kiosk stopped, replace the fresh empty state with the backup:

```
scp ~/Code/OpenObject/Backup/oo-backup-YYYYMMDD.tgz mattlhx@<4c-address>:/tmp/
ssh -t mattlhx@<4c-address> 'sudo systemctl stop openobject-kiosk openobject-player && sudo rm -rf /var/lib/openobject/data /var/lib/openobject/uploads && sudo tar -xzf /tmp/oo-backup.tgz -C /var/lib && sudo chown -R openobject:openobject /var/lib/openobject && sudo systemctl start openobject-player openobject-kiosk && rm /tmp/oo-backup.tgz'
```

Then, from a browser on the Mac, open the 4C's control panel:

- [ ] Library count matches the frame's
- [ ] The pin and the rotation settings carried over
- [ ] A Connected piece plays (the mirrors restored)
- [ ] CoE #03 pinned on the bench monitor: watch it, and note the GPU-process CPU share with the
      same read-only sample used on 2026-10-31 if a number is wanted
- [ ] Software Update in the control panel reports the current version

### 4.6 Square-panel check

The bench monitor is not square. The 1920 x 1920 mode comes from the panel's EDID and the
i915 driver read it on the 3Q; the 4C's graphics use the same driver. This can only be
confirmed on the frame itself, in §5, and it is the one thing the bench cannot prove.

## 5. The swap

1. Power the frame down by unplugging its cord. Photograph the back once more.
2. Note which HDMI port the controller's lead occupies. Slide the 3Q up, unplug the extension,
   the HDMI lead and the power lead. Set the 3Q aside **unmodified**.
3. Slide the 4C in. Power lead into the USB-C beside Ethernet (position 7). HDMI into the same
   position as before. The new angled cable into the USB-C at position 1, flipped so the cable
   exits toward the hub's path; the hub's 2 ft cord does the reaching.
4. **Leave the keyboard's receiver inside the frame.** Plug the K400's USB receiver into the
   UGREEN hub on the end of the angled cable and tuck the hub inside the frame's back. The
   wireless keyboard then reaches the frame's console at any time (Ctrl+Alt+Fn+F2, HANDOFF §15)
   without opening anything, and the hub keeps a free port for a USB stick. The receiver draws
   nothing worth noticing and the kiosk ignores an idle keyboard.
5. Replug the cord. The unit must start by itself (the §4.3 check). The MeLE logo replaces the
   Infinite Objects splash; that is the firmware, not a fault.
6. The art should appear at 1920 x 1920 within about a minute. Open `http://openobject.local`.

- [ ] Starts on power return
- [ ] Full square picture, no letterboxing from a 1920 x 1080 fallback
- [ ] Control panel reachable at `openobject.local`
- [ ] CoE #03 compared against the before state

## 6. Trial and rollback

Keep the 3Q on a shelf, powered off, for at least a week of normal rotation. It is never
written to during this procedure, so rollback is purely physical: unplug the 4C, slide the 3Q
back, reconnect the same three leads, replug the cord. It boots and plays the library as it
was on backup day. Anything added to the library on the 4C after the swap lives only on the 4C.

After the trial, update HANDOFF §2 (the hardware table, the port list, and the barrel-jack
error) and the Setup Guide's parts list for anyone else reviving an XXL with a 4C, in the same
change (HANDOFF §16).

### 6.1 Revisit the quality concessions made for the 3Q

Matt's ask (2026-10-31): with faster hardware, see whether the quality the frame gave up to run
smoothly can be given back. The record shows three places that bent to the N5105, and they are
not alike:

| Piece | What was done for the frame | On the 4C |
|---|---|---|
| *Conservation of Energy* (CoE), all 22 tokens | Nothing visual. The page has no quality setting and already draws at pixel density 1; the one change was the injected clock (HANDOFF §20, 2026-10-26), which keeps the 10-second tempo by drawing fewer frames when the screen falls behind. A faster screen simply draws more of them | Nothing to undo. Watch CoE #03 and the heavy tokens #04 and #14 and record the frame rate; that is the measure of the upgrade |
| *Tiles* (Rich Caldwell) | Display defaults to **Tiled (Low)** resampling because Medium still stuttered on the frame (commits 8078ab5, 4120a29, 70af43f, 2026-07-12). High is the sharpest downscale; Low is the artist's own default | Try **Tiled (Medium)**, then **High**, on the frame, each for a full shuffle cycle. Keep the highest that holds its frame rate. The default in `collections.js` stays Low for other owners' 3Q frames unless the 4C becomes the documented hardware |
| *inkField* (Aluan Wang) | `framePixelDensity: 1` on a frame display (HANDOFF §20, 2026-07-29): a quarter of the pixels, CSS-upscaled, because pixel density 2 stuttered and a two-piece crossfade dropped the WebGL context | This one is bound on the **GPU** (per-frame full-canvas shaders), and the 4C's GPU is only a step up, not the CPU-sized step. Try density 2 once, with a crossfade into another piece, and expect it may still need to stay at 1 |

Add the outcome of each to the decision log below.

## 7. Decision log

- **2026-10-31.** Diagnosis run on the live frame from Terminal.app (three read-only passes and
  one that added a localhost-only DevTools port to the kiosk and removed it again). Matt accepted
  the single-thread finding and the expected gain, ordered the 4C and the angled cable from
  Amazon, and asked for this runbook. Open checks going in: the frame's power lead on the new
  unit, the Wi-Fi chip, the Auto Power On setting, and the angled cable clearing the gap.
- **2026-10-31, later.** Matt asked that the quality concessions be reviewed on the new hardware,
  thinking of CoE. The record says CoE lost none (its clock is lossless); the concessions are
  Tiles' Low resampling default and inkField's pixel density 1. Written up as §6.1.
- **2026-11-05.** The 4C and the angled cable arrived. Matt set the outcome for the project: a
  clean runbook, or updates to the existing docs, that let someone (or Matt later) swap the mini
  PC, with two paths: a frame already running OpenObject (this document: backup, install,
  restore) and one that is not (the Setup Guide's install with a 4C parts list and the 4C
  differences). The two differ only by the backup before and the restore after. The work runs
  slowly between other tasks, one step at a time, and each step is written back here as it
  actually went.


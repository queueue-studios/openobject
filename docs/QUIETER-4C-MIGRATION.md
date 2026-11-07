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

## 2. Parts: what this swap used

The exact items, so the next person can order the same ones. Amazon listing numbers are given
where the part was bought for this project; the two June parts are named by model.

| Part | Exact item | Role |
|---|---|---|
| Mini PC | **MeLE Quieter 4C**, Intel N150 (2025 revision), 16 GB DDR4, 512 GB NVMe SSD, Wi-Fi 5. Amazon **B0DZGRLFLQ**, about $300. Ships with Windows 11 Pro (wiped), a 12 V / 2 A USB-C adapter (used on the desk only) and a VESA plate (unused) | Replaces the Quieter 3Q |
| HDMI link | One of three Alvin's Cables 8K HDMI 2.1 camera-rig cables with angled plugs: 30 cm right-to-right **B08B4PNST7** (model CBWWHDMINEW), 30 cm left-to-right **B07WMPGJQ7** (HDMIRR30), 25 cm straight-to-left **B0CBK34GFR** (LZHDMI25). **Which one fit: to be filled in when it arrives** | Joins the 4C's HDMI 2 to the controller across the 1 3/16 inch gap, since the 3Q's rigid coupler no longer reaches (§5) |
| Keyboard | **Logitech K400 Plus**, wireless keyboard with touchpad on one USB receiver | BIOS, the Debian installer, and the console afterward; the receiver stays in the frame, in one of the three side USB-A ports |
| USB stick | Any **USB-A** stick, 8 GB or larger. Flashed with the Debian 13 netinst image; nothing else lives on it | The installer, used once on the desk |
| Monitor | Any monitor with an HDMI input, borrowed for the desk session | Install and bench checks only |

Not needed on the 4C: the CableCreation CC0516 left-angle USB-A extension, the UGREEN 25946
USB hub, the CybNemo angled USB-C to USB-A cable bought for this swap (Amazon B0FR9KWQVW), and
the AGVEE 8K male-to-male HDMI coupler (its geometry no longer matches). The first three all
served one belief from the June install: that only the port on the upper edge was reachable
with the unit mounted. On 2026-11-05, with the 4C in the bracket, Matt found the **three side
USB-A ports reachable after all**; the keyboard receiver, a stub a quarter inch long, goes
straight into one of them, and the installer stick into another on the desk. The June note in
HANDOFF §2 that "only one USB-A port is realistically free" is corrected in §6.

Same shell to the millimeter: 131 x 81 x 18.3 mm, 203 g, so the bracket and the slide-in fit are
unchanged, apart from the mounting-hole offset described in §5. MeLE sells the identical build
direct in two grades (SE-Grade, Business-Grade) at a much higher price; Amazon's unit is the same
hardware.

## 3. The back of the frame

The mini PC sits below the panel's controller board with its port edge facing **up**, into a
gap of about one centimeter. Everything plugs in along that edge. The two screws on the bracket
directly above the mini PC retain captive nuts inside the chassis: **do not touch them**
(HANDOFF §4). Insert trick: slide the unit up to free the HDMI and USB-C, seat the plugs,
reseat, slide back down.

Port order along that edge, left to right as seen from behind the frame:

| Position | Quieter 3Q (today) | Quieter 4C | What plugs in |
|---|---|---|---|
| 1 | USB-A 3.0 | **USB-C** (data 10 Gbps, DisplayPort, PD in) | on the 3Q, the angled extension looping down to a hub; on the 4C, **nothing**: the keyboard receiver lives in a side port instead |
| 2 | 3.5 mm audio | 3.5 mm audio | nothing |
| 3 | microSD | microSD | nothing |
| 4, 5 | HDMI, HDMI | HDMI, HDMI | the controller's HDMI lead. In the 2026-11-05 photo it appears to sit in the **left** HDMI of the pair, the one nearer the USB-A end; confirm by eye before unplugging and use the same one on the 4C |
| 6 | (none) | CMOS reset pinhole | nothing |
| 7 | USB-C, power only | USB-C, power only (12 V / 2 A) | **the controller's black USB-C power lead**, just right of the HDMI pair in the photo. On the 4C this is the port beside Ethernet, not the new USB-C at position 1. First check when the frame is open: move this lead to the 4C's power port and see the 4C start, before the 3Q comes out of the bracket |
| 8 | Gigabit Ethernet | Gigabit Ethernet | nothing |

The right-hand side carries three USB-A ports on both units. The June install believed them
unreachable with the unit mounted, which is why the 3Q's keyboard came out through position 1
on an angled extension; with the 4C in the bracket they turned out to be reachable, and the
keyboard receiver simply sits in one. The 3Q is powered over USB-C, not a
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
  keyboard to the computer and works in the BIOS and the installer with no driver. The receiver
  goes in one of the 4C's three side USB-A ports and the Debian stick in another. (On the day,
  the receiver rode an angled USB-C cable bought on the June belief that the side ports would be
  blocked in the frame; they are not, so the cable is unnecessary and off the list)
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

- [x] Recorded 2026-11-05 from the installed Debian 13 (kernel 6.12.115+deb13.1-amd64), with
      `lspci -nnk | grep -iA3 -E "network|vga"; lsblk -d -o NAME,SIZE,MODEL; ip -br a`:
      iGPU **Intel Alder Lake-N [8086:46d4]**, driver `i915`; Wi-Fi **Intel CNVi [8086:54f0]**,
      subsystem [8086:0034], driver `iwlwifi`, interface `wlp0s20f3`; wired `enp1s0` (Realtek
      RTL8111/8168, `r8169`); drive **`nvme0n1`, 476.9 GiB, BIWIN CE480Y2D100-512G**. The
      installer's Debian screens that differed from the 3Q run are listed under §4.4

### 4.3 BIOS

Done 2026-11-05 on the desk. The 4C's firmware is Intel's full reference setup (AMI Aptio
2.22.1293), so the menus run deep; these are the paths as found:

- **Getting in.** Connecting power does nothing on a fresh unit (Auto Power On ships off, see
  below). Press the power button, then tap `Del` repeatedly; it lands in Setup. The first boot
  otherwise goes to Windows' "Just a moment" setup screen, which is harmless.
- **Secure Boot off:** Security, then Secure Boot, then set **Secure Boot** from Enabled to
  Disabled. It changed without needing a mode switch.
- **Auto Power On:** Advanced, then **Customer Exclusive Functions** (MeLE's own page,
  second-to-last on the Advanced list), then **Auto Power On** from Disabled to **Enabled**.
  Intel's own State After G3 setting was not found on the Chipset pages; MeLE's switch is the
  one that works.
- **Leave alone:** the clock (Debian sets it from the network and keeps the hardware clock in
  universal time, so the BIOS will read hours off afterward), Fast Boot, and the power limits.
- **Save:** `F4`, Yes. The unit reboots. Boot Option #1 stays the Windows drive for now; the
  installer is reached through Boot Override, not by reordering.
- **The test:** with Windows' setup screen up, pull the adapter from the wall, wait five
  seconds, plug it back in. The unit started by itself. This is the behavior the frame depends on.

- [x] Secure Boot disabled
- [x] Auto Power On enabled, confirmed by replug

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
- **Two screens the 3Q install did not show (2026-11-05).** Right after the language screens,
  "Detect network hardware" says some hardware needs non-free firmware and lists
  `iwlwifi-so-a0-jf-b0-78.ucode` through `-89.ucode`, asking whether to load them from removable
  media. Answer **No**: those are newer versions the stick does not carry, the driver falls back
  to one it has, and the radio works. The list itself is good news, since it names the Wi-Fi as
  Intel on `iwlwifi`. Then "Configure the network" offers two interfaces: `enp1s0`, the Realtek
  wired port, and **`wlp0s20f3`, Intel Corporation CNVi Wi-Fi**. Pick the wireless one.
- The disk to wipe is the **BIWIN CE480Y2D100-512G** NVMe drive, about 477 GB; the PNY stick is
  the other entry in the list.

- [x] Debian 13.7 installed on the SSD 2026-11-05, boots to the `openobject login:` console.
      Screens beyond the June notes: time zone (Eastern), mirror country (United States),
      archive (`deb.debian.org`), proxy (blank), popularity contest (No). Username `mattlhx`,
      the same as the frame, so every command here keeps working
- [x] `install.sh` run 2026-11-05, from the Mac over SSH rather than at the console. The SSH
      server was installed first at the console (`sudo apt update && sudo apt install -y
      openssh-server git`), then from Terminal.app: `ssh mattlhx@<address>`, the `git clone`
      line from `installer/README.md`, and the installer **detached** so the Wi-Fi handoff
      inside it could not kill it along with the session:
      `sudo systemd-run --unit=oo-install --collect -p StandardOutput=append:/var/log/oo-install.log -p StandardError=append:/var/log/oo-install.log bash /opt/openobject/installer/install.sh && sleep 2 && sudo tail -f /var/log/oo-install.log`.
      The installer found the Wi-Fi credentials Debian had saved and asked nothing. Step 9
      moved the radio to NetworkManager on a **fresh install**, the path HANDOFF §20 2026-08-08
      left as pending device verification: `wlp0s20f3` connected, gateway reachable, the
      watchdog restarted NM-aware, the player answered `/healthz` at version 1.10.0. The DHCP
      address changed with the handoff (192.168.1.177 to .176); use the new one. The undo
      timer it arms is disarmed after the reboot proves the network returns:
      `sudo systemctl disable --now oo-net-revert.timer`

### 4.5 Restore the data

With the player and kiosk stopped, replace the fresh empty state with the backup. Done
2026-11-05 from Terminal.app; the copy took 20 seconds over Wi-Fi:

```
scp ~/Code/OpenObject/Backup/oo-backup-20261105.tgz mattlhx@192.168.1.176:/tmp/
ssh -t mattlhx@192.168.1.176 'sudo systemctl stop openobject-kiosk openobject-player && sudo rm -rf /var/lib/openobject/data /var/lib/openobject/uploads && sudo tar -xzf /tmp/oo-backup-20261105.tgz -C /var/lib && sudo chown -R openobject:openobject /var/lib/openobject && sudo systemctl start openobject-player openobject-kiosk && rm /tmp/oo-backup-20261105.tgz && echo "restore done"'
```

Then compare the restored unit against the backup rather than against the old frame, which
need not be awake for it. On the Mac, `sqlite3` reads the database straight out of the archive
(`tar -xzf ... openobject/data/openobject.sqlite*`, then `select kind, count(*) from library
group by kind`, `select count(*), sum(in_rotation) from library`, and the `settings` rows). On
the unit, a read-only script asks the same questions through `node:sqlite` plus the file counts.

- [x] Library 55 rows (5 animated, 35 connected, 13 still, 2 video), 12 in rotation, 20 upload
      files, 18 Connected mirrors, rotation `sequence`, sort `recent`, no pin, the sleep ranges:
      identical on both sides. Ownership `openobject:openobject`, both services active, player
      answering at 1.10.0
- [x] The desk monitor showed the OpenObject idle screen after the reboot and the **sleep
      screen** after the restore, because the restored sleep schedule covers that hour. That is
      the settings carrying over, not a fault. The backup held no pin, so no particular piece
      was expected
- [ ] Software Update in the control panel reports the current version (check on the frame)

Two things learned here for the next person. The installer's closing text says "THE UNDO IS
STILL ARMED" and tells you to disable `oo-net-revert.timer`; on a fresh install that timer does
not exist (the installer runs the handoff with the guard off), so the disable fails harmlessly
and the message is wrong for this path. And the bench monitor leaves nothing behind: Linux reads
the connected panel's description at every kiosk start and picks its native mode fresh, so a
unit installed on a desk monitor shows the square panel correctly the moment it is plugged in.

### 4.6 Square-panel check

The bench monitor is not square. The 1920 x 1920 mode comes from the panel's EDID and the
i915 driver read it on the 3Q; the 4C's graphics use the same driver. This can only be
confirmed on the frame itself, in §5, and it is the one thing the bench cannot prove.

## 5. The swap

> **Found during the swap, 2026-11-05: the 4C does not hang where the 3Q did.** The frame's
> bracket, behind the panel, holds the mini PC by two screw heads left proud of the unit's back
> (the screws go in the VESA holes but are not tightened flush; the gap under the head hooks the
> bracket). The 4C's VESA holes sit about a quarter inch lower than the 3Q's, so hung on the same
> bracket its port edge lands farther from the controller board. The power and USB-C leads are
> flexible and do not care. The HDMI link does: the 3Q was connected through a rigid **AGVEE 8K
> male-to-male HDMI coupler**, 0.75 inch of body between two plugs that face opposite ways
> (the controller's port and the mini PC's port are upside down to each other), and with the 4C
> hung it falls about half an inch short. Moving the bracket was ruled out: it is screwed into
> the thin plastic sheet that protects the panel, and dust falling behind the panel is the risk.
> Taping the unit in place was ruled out too, since the fanless case needs air around it. The
> fix Matt chose: **use the 4C's other HDMI port.** Infinite Objects used the mini PC's HDMI 1
> because it lines up exactly with the controller's port, which is what made the rigid coupler
> possible. HDMI 2 sits to the left of the controller's port, so a short cable with an angled
> plug at each end can lie along the edge between the two with room for both plugs. Nothing in
> the software cares which port carries the panel. Ordered 2026-11-05, two 30 cm Alvin's Cables
> 8K HDMI 2.1 camera-rig cables, one right-to-right angle (B08B4PNST7, model CBWWHDMINEW) and
> one left-to-right (B07WMPGJQ7, model HDMIRR30), because the two ports face each other upside
> down and which pair of bends lies flat is not knowable from a photo. Until one arrives the
> frame rests open with the 4C in place and the wall dark, by Matt's choice: putting the 3Q back
> was more work than the wait.


1. Power the frame down by unplugging its cord. Photograph the back once more.
2. Note which HDMI port the controller's lead occupies. Slide the 3Q up, unplug the extension,
   the HDMI lead and the power lead. Set the 3Q aside **unmodified**.
3. Slide the 4C in. Power lead into the USB-C beside Ethernet (position 7). HDMI into HDMI 2
   with the angled cable (§5 note above). Position 1 stays empty.
4. **Leave the keyboard's receiver inside the frame,** in one of the three side USB-A ports.
   The wireless keyboard then reaches the frame's console at any time (Ctrl+Alt+Fn+F2, HANDOFF
   §15) without opening anything. The receiver draws nothing worth noticing and the kiosk
   ignores an idle keyboard. No cable and no hub are needed.
5. Replug the cord. The unit must start by itself (the §4.3 check). The MeLE logo replaces the
   Infinite Objects splash; that is the firmware, not a fault.
6. The art should appear at 1920 x 1920 within about a minute. Open `http://openobject.local`.

- [ ] Starts on power return
- [ ] Full square picture, no letterboxing from a 1920 x 1080 fallback
- [ ] Control panel reachable at `openobject.local`
- [ ] **Keyboard check from inside the frame:** with the receiver in its side port, press
      Ctrl+Alt+Fn+F2 on the K400; the console login must replace the art. Ctrl+Alt+F1 brings the
      art back. Matt asked for this check explicitly, since the side-port placement is new
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
- **2026-11-05, afternoon.** Desk work complete and verified; swap begun. The 4C's mounting
  holes sit a quarter inch from the 3Q's, so the rigid 0.75 inch flipped HDMI coupler no longer
  reaches by about half an inch (§5). Matt is choosing between lengthening the rigid link (a
  short straight male-to-female HDMI adapter ahead of the existing coupler) and a flexible one
  (a short flat ribbon HDMI cable with low-profile angled plugs). The frame waits open until the
  part arrives.
- **2026-11-05, evening.** Matt's answer to the offset: the 4C's HDMI 2, which sits beside the
  controller's port rather than under it, with a short double-angled cable. Two Alvin's Cables
  30 cm angled HDMI cables ordered (right-to-right and left-to-right) to cover the bend
  directions. Waiting on delivery.
- **2026-11-05, later.** The 4C is in the bracket with the controller's USB-C power lead on its
  power port (the lead had the half inch of slack the new position needed). The K400 receiver
  first rode the angled USB-C cable on the left-end port; later the same day Matt found the
  three side USB-A ports reachable with the unit mounted, moved the receiver to one, and the
  cable came off the parts list. The gap
  between the 4C's port edge and the controller measures **1 3/16 inch**, room for angled HDMI
  plugs; the power lead's position dictates which way the plug beside it must bend. A third
  cable ordered to cover that: Alvin's Cables 25 cm straight-to-left-angle (B0CBK34GFR, model
  LZHDMI25). A straight plug stands about 0.8 inch off its port and needs its bend inside the
  remaining space, so it is the fallback of the three. The frame stays face down on a protected
  surface until a cable fits.
- **2026-11-06.** The **left-to-right** 30 cm cable (B07WMPGJQ7) fits between HDMI 2 and the
  controller, awkwardly and a bit snug. A fourth cable arrives 2026-11-07 for comparison:
  Alvin's Cables ultra-thin (2.4 mm) 8K HDMI 2.1, **left-to-left angle**, 30 cm, Amazon
  **B0DQL5S49L** (model LLHDMI30RD). If it lies better it wins; otherwise the left-to-right is
  the part. The right-to-right (B08B4PNST7) and straight-to-left (B0CBK34GFR) did not fit.


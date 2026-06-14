# Install walkthrough — bench notes (raw capture)

> Working scratchpad from the real Phase-2B bench run (2026-06-14). These are the
> novice-tripping details discovered while actually doing the install. **To be distilled into
> `docs/SETUP-GUIDE.md` (casual) + `installer/README.md` (builder) once the full run is
> verified end-to-end** — so the guide documents the path that actually worked, not a guess.
> `[✓]` = confirmed at the bench · `[ ]` = still pending in this run.

## On the Mac
- [✓] **balenaEtcher build:** Apple Silicon Macs (M1–M4) → download **macOS (ARM64)**; Intel Macs → x64. (The Debian ISO stays **amd64** regardless — that's for the frame's chip, not the Mac.)
- [✓] **Which Debian ISO:** from the `iso-cd` folder pick the **plain** `debian-<ver>-amd64-netinst.iso`. **Not** `debian-edu-…` (school edition) and **not** `debian-mac-…` (that's for installing onto Apple hardware — misleading when you're downloading *from* a Mac).
- [✓] **Code/seed stick format:** **MS-DOS (FAT)** (best for ≤32 GB; max compatibility with minimal Linux) or **exFAT** (>32 GB). **Never** a Mac-only format (APFS / Mac OS Extended) — the frame's Linux can't read it. Scheme: Master Boot Record.
- [✓] **Debian stick needs no formatting** — Etcher overwrites the whole stick.
- [✓] **After Etcher finishes, macOS pops "The disk you inserted was not readable":** that's normal (it's now a Linux disk). Click **Eject** — **never "Initialize"** (Initialize would wipe the installer you just made).
- [✓] **Eject the seed stick properly** (⏏ in Finder) so the file finishes writing before unplugging.

## At the frame — boot
- [✓] **Enter BIOS:** tap **`Del`** repeatedly from the instant it powers on (Quiet Boot hides the prompt). K400: make sure its power switch is ON.
- [✓] **Boot the stick:** BIOS → **Save & Exit → Boot Override** → pick the **plain** `UEFI: <stick name>` line. If the stick shows **two** UEFI lines (e.g. "…" and "…, Partition 2"), the **plain one** is the right first choice; "Partition 2" is only a fallback.
- [✓] **Debian menu:** choose **Graphical install**.

## At the frame — Debian installer screens
- [✓] **Network:** pick the **wireless / Wi-Fi** interface (not wired Ethernet, which has no cable). Security type = **WPA/WPA2 PSK** (not WEP/Open). Then the Wi-Fi passphrase.
- [✓] **Hostname** = `openobject`; **Domain** = blank.
- [✓] **Root password = LEAVE BLANK** (both boxes empty) → this makes the first user an admin (`sudo`), which the Phase-3 install command needs. Remember the username + password.
- [✓] **Partition disks:** "Guided - use entire disk" → on the disk list pick the **eMMC by its `MMC A3V012` id + ~125 GB / 116 GiB size**, **not** the **"PNY … USB" stick (~31 GB)**. Then "All files in one partition." Guided layout came out as: 1 GB **ESP** + ~117 GB **ext4 `/`** + ~6.5 GB **swap**. "Finish partitioning…" → **"Write the changes to disks? → Yes"** (the wipe).
  - **⚠ Device-name gotcha:** the eMMC enumerated as **`mmcblk1`** in the Debian installer but **`mmcblk0`** in the Ubuntu live session (the empty microSD slot can grab `mmcblk0`). **Identify the eMMC by the `A3V012` id + ~116 GiB size, NOT a fixed `mmcblkN`.** → reconcile the hardcoded `/dev/mmcblk0` in HANDOFF §2/§4 and the backup appendix (capture-only `ddrescue` target) to say "the ~116 GiB `A3V012` eMMC — usually `mmcblk0`, possibly `mmcblk1`; confirm with `lsblk` by size/id."
- [✓] **Software selection (tasksel):** highlight + **Spacebar** to UNcheck **"Debian desktop environment"** AND **"… GNOME"** (uncheck both — the GNOME sub-item stays ticked otherwise); keep only **"standard system utilities"** ✓. End state = a single ✓ on "standard system utilities". (web/SSH server left unchecked — SSH not used in this bench flow.)
- [✓] **GRUB:** on this UEFI box it **installed automatically — no "which device?" or "force removable path?" prompt** (writes grub-efi to the ESP + makes a "debian" UEFI boot entry). So the guide should say "on UEFI, GRUB just installs itself." (Keep the device-pick guidance only as a note for the rare BIOS/legacy case.)
- [✓] **Finish → "Installation complete":** safe to **unplug the Debian stick before clicking Continue** (all writing is done). Reboots to a **text console login** (no desktop). **Password is invisible while typing** at the console login — warn users it's not a dead keyboard.
- [ ] If it does NOT boot to Debian (lands in BIOS / "no bootable device"): Boot Override → the **debian / eMMC** UEFI entry, or set it first in boot order. (Stale factory "ubuntu (A3V012)" NVRAM entry may linger but is harmless.)

## Hardware confirmed at the bench (2026-06-14, `lspci -nnk` on Debian 13.5 / kernel 6.12.90)
- **Wi-Fi (fills §19):** Intel **Jasper Lake PCH CNVi Wi-Fi `[8086:4df0]`**, driver **`iwlwifi`** (FCC TX ID `PD99560D2`). Driven by Debian's in-box `firmware-iwlwifi` — joined Wi-Fi in the installer, **no dongle needed**. The biggest Phase-2 risk is now fully closed.
- **iGPU:** Intel **JasperLake UHD Graphics `[8086:4e61]`**, driver **`i915`** (good for cage + Chromium).
- **Wired NIC:** Realtek **RTL8111/8168 `[10ec:0123]`**, driver **`r8169`**.
- **Panel resolution:** **1920×1920** confirmed 2026-06-14 (`fb0/virtual_size` = running; native DRM mode = 1920×1920; 1920×1080 also advertised as a non-square fallback). Square 1:1, matches the app's resolution-independent `100vw×100vh` stage. **Still TBD:** RAM.

## Phase 3 (after Debian boots) — pending
- [ ] Plug in the **OPENOBJECT** seed stick now; mount it; `git clone …bundle /opt/openobject`; `sudo bash …/installer/install.sh`.

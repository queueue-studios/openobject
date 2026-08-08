#!/usr/bin/env bash
# OpenObject installer — provision a minimal Debian into an OpenObject appliance (HANDOFF §3, §4).
#
# Run this ONCE on a freshly-installed minimal Debian, after the OpenObject checkout has been
# placed at /opt/openobject (see installer/README.md for the bench procedure). It is idempotent:
# safe to re-run if a step fails. It NEVER touches /var/lib/openobject (the library + art).
#
#   sudo bash /opt/openobject/installer/install.sh
#
# What it does, in order (network-dependent work first, the Wi-Fi handoff last):
#   1. Install OS packages: Chromium + cage (kiosk), Avahi (openobject.local), NetworkManager + iw,
#      Intel iGPU drivers, polkit (for the Reboot / Shut down power controls), fonts.
#   2. Install Node 22 from NodeSource (Debian's Node is too old for node:sqlite).
#   3. Create the `openobject` service user + runtime dirs, and grant it reboot/poweroff (polkit).
#   4. Point the checkout's git origin at GitHub (so self-update works) + npm install.
#   5. Install + enable the two systemd units (player + kiosk) that replace supervisor.js.
#   6. Set the hostname to `openobject` and start Avahi → reachable at openobject.local.
#   7. Quiet the boot (no console spew / blanking / cursor on the panel).
#   8. Disable Wi-Fi power-save (keeps the frame discoverable and connected; HANDOFF §3).
#   9. Hand Wi-Fi to NetworkManager via installer/net/nm-handoff.sh (non-fatal: a failure
#      restores the working Wi-Fi and carries on).
set -euo pipefail

# ── Config (override via env if needed) ─────────────────────────────────────────────
OO_USER="${OO_USER:-openobject}"
OO_GROUP="${OO_USER}"
OO_HOME="/home/${OO_USER}"
TARGET="${OO_TARGET:-/opt/openobject}"          # where the OpenObject checkout lives on the device
DATA_ROOT="${OO_DATA_ROOT:-/var/lib/openobject}" # runtime data (library, uploads, browser profile)
OO_ORIGIN="${OO_ORIGIN:-https://github.com/queueue-studios/openobject.git}"

# Where this script (and thus the checkout it belongs to) actually is, so we can seed /opt if run
# from a USB stick instead of from an already-cloned /opt/openobject.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"      # installer/ -> repo root

log()  { printf '\n\033[1;36m▶ %s\033[0m\n' "$*"; }
ok()   { printf '  \033[1;32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[1;33m! %s\033[0m\n' "$*" >&2; }
die()  { printf '\n\033[1;31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
run_as_oo() { runuser -u "$OO_USER" -- env HOME="$OO_HOME" "$@"; }

# ── 0. Preflight ────────────────────────────────────────────────────────────────────
log "Preflight"
[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo bash $0"
[ -r /etc/debian_version ] || warn "This doesn't look like Debian — continuing anyway."
command -v apt-get >/dev/null || die "apt-get not found — this installer targets Debian."
ok "root on $( . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-unknown}" )"

export DEBIAN_FRONTEND=noninteractive

# ── 1. OS packages ──────────────────────────────────────────────────────────────────
log "Installing OS packages (this needs network)"
apt-get update
apt-get install -y \
  ca-certificates curl gnupg git \
  chromium cage \
  libgl1-mesa-dri mesa-va-drivers intel-media-va-driver libavcodec-extra \
  avahi-daemon libnss-mdns \
  network-manager iw \
  openssh-server \
  fonts-dejavu-core fonts-liberation \
  || die "apt-get install failed — is the network up?"
ok "packages installed"

# polkit lets the unprivileged `openobject` user run `systemctl reboot` / `poweroff` for the control
# panel's Reboot and Shut down buttons (granted by the rule written in step 3). Package name differs
# across Debian releases: polkitd on bookworm and newer, policykit-1 on bullseye.
apt-get install -y polkitd >/dev/null 2>&1 || apt-get install -y policykit-1 >/dev/null 2>&1 \
  || warn "polkit not installed; Reboot / Shut down may not work until it is"

# SSH is installed and ON by default so a fresh frame is reachable from another computer for
# servicing without a console trip. An owner who wants it closed runs
# `sudo systemctl disable --now ssh`. (Documented in the Setup Guide.) Enabling is idempotent, so
# re-running this installer (a Tier-2 step) never drops an SSH session it is run over.
systemctl enable --now ssh >/dev/null 2>&1 || warn "could not enable ssh (try: sudo systemctl enable --now ssh)"
ok "openssh-server installed and enabled (disable: sudo systemctl disable --now ssh)"

# Console nicety: keep the text-console cursor on at each login. A stray control byte (e.g. from
# dumping a binary file to the screen) can leave the Linux VT cursor hidden until something turns
# it back on; this restores it on every console login. Harmless over SSH.
cat > /etc/profile.d/oo-cursor.sh <<'PROFILE'
# OpenObject: keep the Linux text-console cursor visible on login (harmless over SSH).
setterm --cursor on 2>/dev/null || true
PROFILE
chmod 0644 /etc/profile.d/oo-cursor.sh
ok "console cursor kept visible on login"

# ── 2. Node 22 (NodeSource) ─────────────────────────────────────────────────────────
log "Ensuring Node.js >= 22 (node:sqlite needs >= 22.5)"
node_major() { node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; }
if [ "$(node_major)" -lt 22 ]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | bash - || die "NodeSource setup failed"
  apt-get install -y nodejs || die "installing nodejs failed"
fi
[ "$(node_major)" -ge 22 ] || die "Node is still < 22 after install"
ok "node $(node --version) / npm $(npm --version)"

# ── 3. Service user + runtime dirs ──────────────────────────────────────────────────
log "Service user '$OO_USER' + runtime dirs"
if ! id -u "$OO_USER" >/dev/null 2>&1; then
  useradd --create-home --home-dir "$OO_HOME" --shell /bin/bash "$OO_USER"
  passwd -l "$OO_USER" >/dev/null   # no password login; the systemd PAM session still works
fi
# Groups for DRM / GPU / input so cage can drive the panel and read the keyboard. Add each one
# only if it exists (a missing group must not abort the install under `set -e`).
for grp in video render input; do
  getent group "$grp" >/dev/null && usermod -aG "$grp" "$OO_USER" || true
done
install -d -o "$OO_USER" -g "$OO_GROUP" \
  "$DATA_ROOT" "$DATA_ROOT/data" "$DATA_ROOT/uploads" "$DATA_ROOT/chromium"
ok "user ready; runtime data under $DATA_ROOT"

# Power controls: let the player's service user reboot / power off through logind without a password,
# so the control panel's Reboot and Shut down buttons work (HANDOFF section 17). Scoped to $OO_USER
# and just those actions. The -multiple-sessions variants matter because the kiosk (cage) session is
# always active, which makes logind treat a reboot/power-off as affecting other sessions.
install -d -m 0755 /etc/polkit-1/rules.d
cat > /etc/polkit-1/rules.d/49-openobject-power.rules <<POLKIT
// OpenObject: allow the '${OO_USER}' service user to reboot / power off the frame (HANDOFF section 17).
polkit.addRule(function(action, subject) {
  if (subject.user == "${OO_USER}" &&
      (action.id == "org.freedesktop.login1.reboot" ||
       action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
       action.id == "org.freedesktop.login1.power-off" ||
       action.id == "org.freedesktop.login1.power-off-multiple-sessions")) {
    return polkit.Result.YES;
  }
});
POLKIT
chmod 0644 /etc/polkit-1/rules.d/49-openobject-power.rules
systemctl try-restart polkit >/dev/null 2>&1 || systemctl try-restart polkitd >/dev/null 2>&1 || true
ok "power controls granted to $OO_USER (Reboot / Shut down)"

# ── 4. Seed the checkout + git origin + deps ────────────────────────────────────────
log "OpenObject checkout at $TARGET"
if [ "$SELF_ROOT" != "$TARGET" ]; then
  if [ ! -e "$TARGET" ]; then
    if [ -d "$SELF_ROOT/.git" ]; then
      git clone "$SELF_ROOT" "$TARGET"            # committed files only — no data/, uploads/, node_modules/
    else
      install -d "$TARGET"; cp -a "$SELF_ROOT/." "$TARGET/"
    fi
  else
    warn "$TARGET already exists — provisioning it in place (not overwriting)."
  fi
fi
[ -d "$TARGET/player" ] || die "no player/ under $TARGET — is this the OpenObject checkout?"
chown -R "$OO_USER:$OO_GROUP" "$TARGET"

# Self-update runs git as the openobject user against this checkout; declare it safe + point
# origin at GitHub so a fetch knows where to look (goes live when the repo is public).
run_as_oo git config --global --add safe.directory "$TARGET" || true
if [ -d "$TARGET/.git" ]; then
  run_as_oo git -C "$TARGET" remote set-url origin "$OO_ORIGIN" 2>/dev/null \
    || run_as_oo git -C "$TARGET" remote add origin "$OO_ORIGIN" || true
  ok "git origin → $OO_ORIGIN"
else
  warn "$TARGET is not a git checkout — self-update will be unavailable until it is."
fi

log "Installing player dependencies (npm ci)"
# npm ci installs exactly what package-lock.json pins and never rewrites it, so the checkout stays
# clean. (npm install can rewrite the lockfile, which then trips the self-update dirty-tree guard.)
( cd "$TARGET/player" && run_as_oo npm ci --omit=dev --no-audit --no-fund ) \
  || die "npm ci failed (network, or package-lock.json out of sync?)"
ok "dependencies installed"

# ── 5. systemd units ────────────────────────────────────────────────────────────────
log "Installing systemd units (player + kiosk + Wi-Fi watchdog)"
chmod +x "$TARGET"/installer/kiosk/*.sh "$TARGET"/installer/net/*.sh
install -m 0644 "$TARGET/installer/systemd/openobject-player.service"   /etc/systemd/system/
install -m 0644 "$TARGET/installer/systemd/openobject-kiosk.service"    /etc/systemd/system/
install -m 0644 "$TARGET/installer/systemd/openobject-netcheck.service" /etc/systemd/system/
install -m 0644 "$TARGET/installer/systemd/openobject-netcheck.timer"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable openobject-player.service openobject-kiosk.service
# Wi-Fi watchdog: re-ups Wi-Fi only when the frame has already lost its network (the ifupdown
# bring-up at boot does not retry; see installer/net/oo-netcheck.sh). Enable + start now so the
# safety net is live immediately, without waiting for a reboot.
systemctl enable --now openobject-netcheck.timer
ok "units enabled (player + kiosk on boot; Wi-Fi watchdog timer running)"

# ── 6. Hostname + Avahi (openobject.local) ──────────────────────────────────────────
log "Hostname + mDNS"
hostnamectl set-hostname openobject || warn "could not set hostname"
systemctl enable --now avahi-daemon || warn "avahi-daemon not started"
ok "advertising openobject.local"

# ── 7. Kernel command line: quiet boot + reliable reboot ────────────────────────────
log "Setting the kernel command line"
GRUB_DEFAULT_FILE=/etc/default/grub
# reboot=pci makes `systemctl reboot` use the Intel 0xCF9 platform reset. This board's firmware
# default (ACPI reset) intermittently hangs at the POST splash on a warm reboot and needs a cold
# unplug to recover; the 0xCF9 full reset survives it (bench-verified 2026-06-17). Shut down
# (poweroff) uses a separate path and is unaffected.
DESIRED='quiet loglevel=3 consoleblank=0 vt.global_cursor_default=0 reboot=pci'
if [ -f "$GRUB_DEFAULT_FILE" ]; then
  if grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT_FILE"; then
    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$DESIRED\"|" "$GRUB_DEFAULT_FILE"
  else
    printf 'GRUB_CMDLINE_LINUX_DEFAULT="%s"\n' "$DESIRED" >> "$GRUB_DEFAULT_FILE"
  fi
  command -v update-grub >/dev/null && update-grub || warn "update-grub failed (non-fatal)"
  ok "kernel cmdline set: $DESIRED"
else
  warn "no $GRUB_DEFAULT_FILE — skipping boot-quieting (non-fatal)"
fi

# ── 8. Wi-Fi radio: disable power-save (keeps the frame discoverable + connected) ────
# The XXL's Intel iwlwifi radio defaults to power-save ON, which lets it doze when idle. On the
# frame that shows up two ways: it silently drops off mDNS discovery (goes invisible to the Mac /
# Apple TV apps while still displaying art), and, worse, it occasionally drops its Wi-Fi association
# entirely until a power-cycle. Turning power-save off fixes both. The modprobe drop makes "off" the
# driver default from every boot (independent of whether ifupdown or NetworkManager ends up owning
# the link, since it is set at the driver level); the runtime `iw` call applies it now, so a re-run
# on a live frame needs no reboot. Both best-effort.
log "Disabling Wi-Fi power-save"
cat > /etc/modprobe.d/iwlwifi-openobject.conf <<'MODPROBE'
# OpenObject: keep the Wi-Fi radio awake so the frame stays discoverable and connected (HANDOFF §3).
options iwlwifi power_save=0
options iwlmvm power_scheme=1
MODPROBE
chmod 0644 /etc/modprobe.d/iwlwifi-openobject.conf
wifi_now=""
for d in /sys/class/net/*; do
  [ -e "$d/phy80211" ] && { wifi_now="$(basename "$d")"; break; }
done
[ -n "$wifi_now" ] && iw dev "$wifi_now" set power_save off >/dev/null 2>&1 || true
ok "Wi-Fi power-save disabled (now + persistent)"

# ── 9. Hand Wi-Fi to NetworkManager (non-fatal) ─────────────────────────────────────
# Do this LAST: every step above needed the network the Debian installer set up.
#
# The handoff lives in installer/net/nm-handoff.sh rather than inline here, so the fresh-install
# path and the retrofit path (an existing frame still on ifupdown) share ONE implementation, and
# it is the implementation that has actually been run on real hardware (the XXL, 2026-08-08).
#
# The inline version this replaces could never succeed. Debian marks any interface named in
# /etc/network/interfaces as UNMANAGED by NetworkManager, so NM could not join while ifupdown
# still owned the radio, but the step only retired the ifupdown config AFTER NM had proved
# itself: a deadlock, so every frame installed by that version stayed on ifupdown. The script
# breaks it by freeing the device FIRST, having snapshotted the config so any failure restores it.
#
# OO_ARM_GUARD=0 because the owner is at the keyboard during an install: the persistent
# revert-and-reboot guard that a remote retrofit needs would be the wrong trade here. A failure
# still restores the old Wi-Fi, in place, and we carry on with a warning exactly as before.
log "Handing Wi-Fi to NetworkManager"
if OO_ARM_GUARD=0 bash "${SELF_ROOT}/installer/net/nm-handoff.sh"; then
  ok "Wi-Fi is on NetworkManager"
else
  warn "Wi-Fi handoff skipped, the existing connection still works."
fi

# ── Done ────────────────────────────────────────────────────────────────────────────
log "Smoke test"
systemctl restart openobject-player.service || true   # start it now (NOT the kiosk — it would grab tty1)
sleep 3
if curl -fsS --max-time 5 http://localhost/healthz; then
  printf '\n'; ok "player answered /healthz on :80"
else
  warn "player not answering yet — check: journalctl -u openobject-player -n 50"
fi

cat <<EOF

────────────────────────────────────────────────────────────────────
 OpenObject is installed. Reboot to bring up the kiosk on the panel:

     sudo reboot

 After reboot the panel shows the OpenObject screen, and the control
 panel is reachable from any device on the same Wi-Fi at:

     http://openobject.local

 Logs, if anything looks off:
     journalctl -u openobject-player -b
     journalctl -u openobject-kiosk  -b
────────────────────────────────────────────────────────────────────
EOF

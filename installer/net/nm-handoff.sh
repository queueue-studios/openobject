#!/usr/bin/env bash
# OpenObject: move Wi-Fi from ifupdown/wpa_supplicant onto NetworkManager, with an armed
# auto-revert so a failure heals itself with no keyboard and no Ethernet cable.
#
#   sudo systemd-run --unit=oo-wifi-handoff --collect \
#        /opt/openobject/installer/net/nm-handoff.sh
#
# RUN IT DETACHED, exactly as above. This script takes the Wi-Fi down for a moment, which kills
# the SSH session it was started from; run straight from a shell it would be killed halfway and
# leave the radio half-configured. systemd-run puts it in its own unit that survives the drop.
#
# WHY THIS EXISTS. install.sh step 9 tries the same handoff and cannot ever succeed: Debian marks
# any interface named in /etc/network/interfaces as UNMANAGED by NetworkManager, so NM can't join
# while ifupdown still owns the radio, but install.sh only retires the ifupdown config AFTER NM
# has proved itself. Every frame installed that way stays on ifupdown (confirmed on the real XXL,
# 2026-08-08: `wlp0s20f3 wifi unmanaged`). Breaking the deadlock means freeing the device FIRST,
# which is the risky direction, hence the revert timer below.
#
# WHAT IT DOES NOT TOUCH: the library, uploads, settings, or anything under /var/lib/openobject.
# This is network configuration only.
set -euo pipefail

LOG="/var/log/openobject-nm-handoff.log"
SNAP_DIR="/var/backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
SNAP="${SNAP_DIR}/openobject-net-${STAMP}.tar.gz"
REVERT="/usr/local/sbin/oo-net-revert"

exec > >(tee -a "$LOG") 2>&1
log()  { printf '\n▶ %s\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }
die()  { printf '\n✗ %s\n' "$*" >&2; exit 1; }

log "OpenObject Wi-Fi handoff  ($(date))"
[ "$(id -u)" -eq 0 ] || die "run as root"
command -v nmcli >/dev/null || die "nmcli not installed"

WIFI="${OO_WIFI_DEV:-$(nmcli -t -f DEVICE,TYPE device status | awk -F: '$2=="wifi"{print $1; exit}')}"
[ -n "$WIFI" ] || die "no Wi-Fi device found"
ok "Wi-Fi device: $WIFI"

# ── Already done? ───────────────────────────────────────────────────────────────────
if nmcli -t -f DEVICE,STATE device status | grep -q "^${WIFI}:connected$"; then
  ok "NetworkManager already owns $WIFI and it is connected — nothing to do."
  exit 0
fi

# ── The credentials to re-join with ─────────────────────────────────────────────────
SSID="${OO_WIFI_SSID:-}" PSK="${OO_WIFI_PSK:-}"
WPA_CONF="$(ls /etc/wpa_supplicant/wpa_supplicant*.conf 2>/dev/null | head -n1 || true)"
if [ -z "$SSID" ] && [ -n "$WPA_CONF" ]; then
  SSID="$(grep -oP '(?<=ssid=")[^"]+' "$WPA_CONF" | head -n1 || true)"
  PSK="$(grep -oP '(?<=psk=")[^"]+'  "$WPA_CONF" | head -n1 || true)"
fi
[ -n "$SSID" ] || die "could not work out the Wi-Fi name; re-run with OO_WIFI_SSID=... OO_WIFI_PSK=..."
[ -n "$PSK"  ] || warn "no passphrase found — assuming an open network"
ok "will re-join: $SSID"

# ── 1. Snapshot everything we are about to change ───────────────────────────────────
log "Snapshotting the current network config"
mkdir -p "$SNAP_DIR"
tar czf "$SNAP" -C / \
  etc/network/interfaces \
  $( [ -d /etc/network/interfaces.d ] && echo etc/network/interfaces.d ) \
  $( ls /etc/wpa_supplicant/wpa_supplicant*.conf >/dev/null 2>&1 && echo etc/wpa_supplicant ) \
  2>/dev/null || die "snapshot failed — refusing to change anything"
ok "snapshot: $SNAP"

# ── 2. Write the undo, and arm it BEFORE touching the radio ─────────────────────────
# Deliberately NOT a transient `systemd-run` timer: those do not survive a reboot, and a reboot
# (a power blip, the frame's own auto-power-on) is exactly when a broken network config would
# strand the frame with no undo left. Real unit files instead, enabled, so the guard persists.
#
# The revert is also CONDITIONAL: it restores the old config only if the frame is actually
# offline. A firing while everything is fine is then a harmless no-op instead of silently undoing
# a working handoff. Pass --force to roll back deliberately.
log "Arming the automatic undo"
cat > "$REVERT" <<REVERT_EOF
#!/usr/bin/env bash
# Restore the pre-handoff network config and reboot, IF the frame has lost its network.
# Written by nm-handoff.sh on ${STAMP}. Disarm:  sudo systemctl disable --now oo-net-revert.timer
set -uo pipefail
exec >> "$LOG" 2>&1
if [ "\${1:-}" != "--force" ]; then
  gw=\$(ip route show default 2>/dev/null | awk '/default/{print \$3; exit}')
  if [ -n "\$gw" ] && ping -c 1 -W 2 "\$gw" >/dev/null 2>&1; then
    printf '  . undo check (%s): online, leaving the handoff in place\n' "\$(date)"
    exit 0
  fi
fi
printf '\n▶ AUTO-REVERT firing (%s)\n' "\$(date)"
nmcli connection delete openobject-wifi >/dev/null 2>&1 || true
tar xzf "$SNAP" -C / || printf '  ! restoring the snapshot failed\n'
systemctl disable NetworkManager >/dev/null 2>&1 || true
systemctl enable --now openobject-netcheck.timer >/dev/null 2>&1 || true
systemctl disable oo-net-revert.timer >/dev/null 2>&1 || true
printf '  = config restored, rebooting\n'
systemctl reboot
REVERT_EOF
chmod +x "$REVERT"

cat > /etc/systemd/system/oo-net-revert.service <<'UNIT_EOF'
[Unit]
Description=OpenObject: undo the Wi-Fi handoff if the frame has lost its network
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/oo-net-revert
UNIT_EOF

cat > /etc/systemd/system/oo-net-revert.timer <<'UNIT_EOF'
[Unit]
Description=OpenObject: periodic safety check after the Wi-Fi handoff
[Timer]
OnBootSec=90
OnActiveSec=3min
OnUnitActiveSec=3min
AccuracySec=10s
[Install]
WantedBy=timers.target
UNIT_EOF

systemctl daemon-reload
systemctl enable --now oo-net-revert.timer >/dev/null 2>&1 || die "could not arm the undo — refusing to change anything"
ok "undo armed and persistent (survives a reboot); checks every ~3 minutes"
ok "it only fires while the frame is OFFLINE, so it cannot undo a working handoff"
ok "disarm with:  sudo systemctl disable --now oo-net-revert.timer"

# The existing Wi-Fi watchdog re-ups the link whenever it sees no connectivity, and this procedure
# deliberately drops the link for a moment. Left running it would fire mid-handoff and, on its
# second escalation, reload the Wi-Fi driver out from under NetworkManager. Pause it for the
# duration; it is restored at the end (and by the revert).
log "Pausing the Wi-Fi watchdog for the duration"
systemctl stop openobject-netcheck.timer >/dev/null 2>&1 || true
ok "openobject-netcheck.timer stopped"

# ── 3. Free the radio from ifupdown ─────────────────────────────────────────────────
log "Releasing $WIFI from ifupdown"
for f in /etc/network/interfaces /etc/network/interfaces.d/*; do
  [ -f "$f" ] || continue
  if grep -qE '^\s*(allow-hotplug|auto|iface)\s+wl' "$f"; then
    cp -a "$f" "${f}.openobject.bak"
    sed -i -E 's/^(\s*(allow-hotplug|auto|iface|wpa-|address|netmask|gateway|dns-).*wl.*)$/# \1  # disabled by OpenObject (NetworkManager owns Wi-Fi)/' "$f"
    ok "edited $f"
  fi
done
ifdown "$WIFI" >/dev/null 2>&1 || true
pkill -f "wpa_supplicant.*${WIFI}" >/dev/null 2>&1 || true
sleep 2

# ── 4. Hand it to NetworkManager and join ───────────────────────────────────────────
log "Handing $WIFI to NetworkManager"
systemctl enable NetworkManager >/dev/null 2>&1 || true
systemctl restart NetworkManager || { warn "NetworkManager would not start — reverting NOW"; "$REVERT" --force; exit 1; }
sleep 3
nmcli device set "$WIFI" managed yes >/dev/null 2>&1 || true
nmcli radio wifi on >/dev/null 2>&1 || true
sleep 2

joined=0
for attempt in 1 2 3; do
  if nmcli device wifi connect "$SSID" password "$PSK" name openobject-wifi >/dev/null 2>&1; then
    joined=1; break
  fi
  warn "join attempt ${attempt} failed, retrying"
  nmcli device wifi rescan >/dev/null 2>&1 || true
  sleep 5
done
[ "$joined" -eq 1 ] || { warn "could not join $SSID — reverting NOW rather than waiting"; "$REVERT"; exit 1; }
nmcli connection modify openobject-wifi connection.autoconnect yes >/dev/null 2>&1 || true

# ── 5. Prove it actually works before leaving it in place ───────────────────────────
log "Verifying"
sleep 4
nmcli -t -f DEVICE,STATE device status | grep -q "^${WIFI}:connected$" \
  || { warn "NM reports $WIFI not connected — reverting NOW"; "$REVERT"; exit 1; }
ok "NetworkManager reports $WIFI connected"

IP="$(nmcli -t -f IP4.ADDRESS device show "$WIFI" | head -n1 | cut -d: -f2- || true)"
GW="$(ip route | awk '/^default/{print $3; exit}' || true)"
[ -n "$GW" ] || { warn "no default route — reverting NOW"; "$REVERT"; exit 1; }
ping -c 2 -W 3 "$GW" >/dev/null 2>&1 || { warn "gateway $GW unreachable — reverting NOW"; "$REVERT"; exit 1; }
ok "address $IP, gateway $GW reachable"

log "Restarting the Wi-Fi watchdog"
systemctl start openobject-netcheck.timer >/dev/null 2>&1 || warn "could not restart openobject-netcheck.timer"
ok "watchdog back on (now NetworkManager-aware)"

curl -fsS --max-time 8 -o /dev/null http://localhost/healthz \
  && ok "the player is still answering on :80" \
  || warn "player did not answer /healthz (check it separately; this is not a network fault)"

cat <<EOF

────────────────────────────────────────────────────────────────────
 Wi-Fi is now managed by NetworkManager and connected to: ${SSID}
 Address: ${IP}

 THE UNDO IS STILL ARMED. It checks every ~3 minutes and restores the
 old config only if the frame is offline, so it will sit harmlessly
 until you disarm it. It survives a reboot.

 From another device, check BOTH of these work:
     http://openobject.local        (the control panel)
     the art is still on the panel

 Then cancel the undo:
     sudo systemctl disable --now oo-net-revert.timer

 To roll back deliberately at any time:
     sudo ${REVERT} --force
 Snapshot of the old config: ${SNAP}
────────────────────────────────────────────────────────────────────
EOF

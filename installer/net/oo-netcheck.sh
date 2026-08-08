#!/bin/sh
# OpenObject Wi-Fi watchdog (HANDOFF §3, §20): re-up Wi-Fi only when the frame has lost its
# network. The installed frame's Wi-Fi is brought up once at boot by ifupdown (allow-hotplug +
# wpa_supplicant), which does NOT retry: a cold boot where the radio or the access point isn't
# ready in time can leave the frame display-but-no-network until a manual power-cycle. A systemd
# timer runs this every ~30s; it acts ONLY when there is already no connectivity, so it can never
# disturb a working connection (or an SSH session): there is nothing to disturb when it fires.
#
# When it does fire it escalates: re-up the link first, and if that does not revive it (a wedged
# radio does not always reset that way), it forces Wi-Fi power-save off and reloads the Wi-Fi driver,
# which resets the radio the way a reboot would, without rebooting the frame. (Power-save left on is
# the usual root cause of the drop in the first place; the installer disables it, this is the belt.)
#
# The re-up itself depends on WHO owns the radio, and both cases exist in the field. A frame installed
# by install.sh is on ifupdown (its NetworkManager handoff could never succeed, see nm-handoff.sh), so
# ifdown/ifup is right there. A frame that has been through nm-handoff.sh is on NetworkManager, where
# ifdown/ifup does nothing useful and the driver reload would yank the radio out from under NM. So
# check who manages the device and use that stack's own commands.
#
# Device-agnostic on purpose: it finds the wireless interface itself, so it also serves the next
# owner's hardware, not just this frame's wlp0s20f3.
set -u

log() { logger -t openobject-netcheck "$*" 2>/dev/null || true; }

# The wireless interface, discovered generically (sysfs marks Wi-Fi devices with phy80211).
wifi_dev=""
for d in /sys/class/net/*; do
  if [ -e "$d/phy80211" ] || [ -e "$d/wireless" ]; then
    wifi_dev=$(basename "$d")
    break
  fi
done
[ -n "$wifi_dev" ] || exit 0   # no Wi-Fi device (e.g. an Ethernet-only frame): nothing to watch

# Is NetworkManager the one managing this radio? (Only true after nm-handoff.sh has run.)
nm_managed() {
  command -v nmcli >/dev/null 2>&1 || return 1
  state=$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v d="$wifi_dev" '$1==d {print $2; exit}')
  [ -n "$state" ] && [ "$state" != "unmanaged" ] && [ "$state" != "unavailable" ]
}

# Bring the link back up using whichever stack owns it.
bring_up() {
  if nm_managed; then
    nmcli device disconnect "$wifi_dev" >/dev/null 2>&1 || true
    nmcli connection up openobject-wifi >/dev/null 2>&1 \
      || nmcli device connect "$wifi_dev" >/dev/null 2>&1 \
      || log "nmcli could not bring $wifi_dev back up"
  else
    ifdown --force "$wifi_dev" >/dev/null 2>&1
    ifup "$wifi_dev" >/dev/null 2>&1 || log "ifup $wifi_dev failed"
  fi
}

online() {
  # Down if there is no default route, or the default gateway does not answer.
  gw=$(ip route show default 2>/dev/null | awk '/default/ {print $3; exit}')
  [ -n "$gw" ] || return 1
  ping -c 1 -W 2 "$gw" >/dev/null 2>&1
}

# Hysteresis: ignore a momentary blip, acting only if two checks ~5s apart both fail.
online && exit 0
sleep 5
online && exit 0

if nm_managed; then owner="NetworkManager"; else owner="ifupdown"; fi
log "no LAN connectivity via $wifi_dev, re-upping Wi-Fi (managed by $owner)"
bring_up
# Keep the radio awake after the bring-up. An idle Wi-Fi power-save (iwlwifi on the XXL) is the usual
# cause of these drops, of both the silent mDNS-discovery drop and a full disconnect. Best-effort.
iw dev "$wifi_dev" set power_save off >/dev/null 2>&1 || true

# A plain ifdown/ifup does not always revive a wedged Wi-Fi driver (bench-seen on the XXL's iwlwifi:
# the radio stayed dark until a reboot). If we are still offline a few seconds later, reload the
# driver, which resets the radio the way a reboot would, then bring the link back up. This is what
# turns a stuck frame back on without someone walking to the wall.
sleep 8
online && exit 0
drv=$(basename "$(readlink -f "/sys/class/net/$wifi_dev/device/driver" 2>/dev/null)" 2>/dev/null || echo '')
if [ -n "$drv" ]; then
  log "still offline after ifup; reloading Wi-Fi driver ($drv)"
  for up in iwlmvm iwldvm; do modprobe -r "$up" >/dev/null 2>&1 || true; done  # Intel opmode above iwlwifi
  modprobe -r "$drv" >/dev/null 2>&1 || true
  sleep 2
  modprobe "$drv"  >/dev/null 2>&1 || true
  sleep 3
  bring_up
  iw dev "$wifi_dev" set power_save off >/dev/null 2>&1 || true
fi

#!/bin/sh
# OpenObject Wi-Fi setup mode (HANDOFF §11, roadmap E8): when the frame cannot reach any network it
# knows, it raises its OWN Wi-Fi network so the owner can hand it new credentials from a phone. The
# panel shows the setup screen; the phone gets a small page served by the player.
#
#   oo-setup-mode.sh check    decide, and enter/leave/retry as needed (the timer runs this)
#   oo-setup-mode.sh start    raise the AP now
#   oo-setup-mode.sh stop     drop the AP and let NetworkManager reconnect normally
#   oo-setup-mode.sh status   prints "on" or "off"
#
# ONE RADIO, TWO JOBS. The frame has a single Wi-Fi adapter, and it cannot host an access point and
# hunt for the home network at the same time. So while setup mode is on, the frame is NOT trying to
# reconnect. That is why `check` drops the AP every RETRY_EVERY seconds and gives normal autoconnect
# a window: without it, a five-minute router reboot would strand the frame in setup mode until
# someone walked over to it. A brief outage must heal itself.
#
# It is also why entering is slow (OFFLINE_FOR seconds, default 5 minutes) and leaving is quick: a
# frame that can reach the network should never be sitting on its own AP.
#
# WITH ONE EXCEPTION, learned on the real frame: the retry is right for a frame nobody is attending
# and wrong for one with an owner in front of it. If a phone is associated with the AP, standing down
# would drop the very page they are typing into, so the retry is deferred while a client is on.
set -u

STATE_DIR=/run/openobject
FLAG="$STATE_DIR/setup-mode"          # present = the AP is up. /run clears on reboot, by design:
                                      # a rebooted frame re-decides from scratch within a minute.
SINCE="$STATE_DIR/offline-since"      # unix time we FIRST saw the frame offline
AP_CON=openobject-setup-ap
AP_SSID="${OO_AP_SSID:-OpenObject-Setup}"
AP_PSK="${OO_AP_PSK:-openobject}"
AP_ADDR="${OO_AP_ADDR:-192.168.4.1/24}"   # pinned; NM's shared mode would default to 10.42.0.1
OFFLINE_FOR="${OO_OFFLINE_FOR:-300}"              # seconds offline before the AP goes up
RETRY_EVERY="${OO_RETRY_EVERY:-300}"              # seconds of AP before standing down to retry
RETRY_WINDOW="${OO_RETRY_WINDOW:-60}"             # seconds given to normal autoconnect on retry

log() { logger -t openobject-setup-mode "$*" 2>/dev/null || true; }
mkdir -p "$STATE_DIR" 2>/dev/null

wifi_dev() {
  nmcli -t -f DEVICE,TYPE device status 2>/dev/null | awk -F: '$2=="wifi"{print $1; exit}'
}

online() {
  gw=$(ip route show default 2>/dev/null | awk '/default/{print $3; exit}')
  [ -n "$gw" ] || return 1
  ping -c 1 -W 2 "$gw" >/dev/null 2>&1
}

ap_up() { [ -e "$FLAG" ]; }

start_ap() {
  dev=$(wifi_dev); [ -n "$dev" ] || { log "no wifi device; cannot start setup mode"; return 1; }
  # Idempotent: recreate the profile each time so a changed SSID/password/address takes effect and a
  # half-written profile from a previous run cannot linger.
  nmcli connection delete "$AP_CON" >/dev/null 2>&1
  nmcli connection add type wifi ifname "$dev" con-name "$AP_CON" autoconnect no ssid "$AP_SSID" \
    >/dev/null 2>&1 || { log "could not create $AP_CON"; return 1; }
  nmcli connection modify "$AP_CON" \
    802-11-wireless.mode ap 802-11-wireless.band bg \
    ipv4.method shared ipv4.addresses "$AP_ADDR" \
    wifi-sec.key-mgmt wpa-psk wifi-sec.psk "$AP_PSK" >/dev/null 2>&1 \
    || { log "could not configure $AP_CON"; return 1; }
  if nmcli connection up "$AP_CON" >/dev/null 2>&1; then
    : > "$FLAG"
    log "setup mode ON: broadcasting $AP_SSID at ${AP_ADDR%%/*}"
    return 0
  fi
  log "failed to bring up $AP_CON"
  nmcli connection delete "$AP_CON" >/dev/null 2>&1
  return 1
}

stop_ap() {
  nmcli connection down "$AP_CON" >/dev/null 2>&1
  nmcli connection delete "$AP_CON" >/dev/null 2>&1
  rm -f "$FLAG"
  log "setup mode OFF"
}

# Is a phone (or laptop) actually associated with our access point right now? If so the owner is
# mid-setup, and standing down would yank the network out from under the page they are filling in.
# Found on the real frame 2026-08-09: the retry cycle is right for an unattended frame and wrong for
# one with somebody standing in front of it.
ap_has_client() {
  dev=$(wifi_dev); [ -n "$dev" ] || return 1
  n=$(iw dev "$dev" station dump 2>/dev/null | grep -c '^Station')
  [ "${n:-0}" -gt 0 ]
}

# Stand down briefly and let NetworkManager try the networks it knows. Returns 0 if it got back on.
retry_known_networks() {
  log "standing down from the AP to retry known networks"
  stop_ap
  dev=$(wifi_dev)
  [ -n "$dev" ] && nmcli device connect "$dev" >/dev/null 2>&1
  waited=0
  while [ "$waited" -lt "$RETRY_WINDOW" ]; do
    sleep 5; waited=$((waited + 5))
    if online; then log "back on a known network; staying off the AP"; rm -f "$SINCE"; return 0; fi
  done
  return 1
}

case "${1:-check}" in
  start)  start_ap ;;
  stop)   stop_ap ;;
  status) ap_up && echo on || echo off ;;
  check)
    if ap_up; then
      # In setup mode. Age the AP, and periodically give the home network another chance, so a
      # temporary outage does not leave the frame stranded on its own network.
      if ap_has_client; then
        # Someone is connected and presumably typing. Push the next retry out rather than dropping
        # them: touching the flag restarts the age clock.
        touch "$FLAG" 2>/dev/null
        log "a client is on the setup network; holding the AP up"
        exit 0
      fi
      age=$(( $(date +%s) - $(stat -c %Y "$FLAG" 2>/dev/null || date +%s) ))
      if [ "$age" -ge "$RETRY_EVERY" ]; then
        retry_known_networks || start_ap
      fi
      exit 0
    fi

    if online; then rm -f "$SINCE"; exit 0; fi

    # Measured in ELAPSED TIME, not in consecutive checks. A counter is only as good as the cadence
    # driving it: a check that runs late, gets skipped, or sees one momentary blip of "online" resets
    # or starves it, and the wait stretches with no way to tell from outside. On the real frame a
    # nominal 5-minute wait took about 25 (Matt, 2026-08-09). A timestamp cannot drift like that, and
    # it makes the number we tell owners true.
    now=$(date +%s)
    since=$(cat "$SINCE" 2>/dev/null || echo '')
    if [ -z "$since" ]; then echo "$now" > "$SINCE"; since=$now; fi
    elapsed=$((now - since))
    log "offline for ${elapsed}s of ${OFFLINE_FOR}s"
    [ "$elapsed" -ge "$OFFLINE_FOR" ] || exit 0

    log "offline ${elapsed}s; entering setup mode"
    start_ap
    ;;
  *) echo "usage: $0 {check|start|stop|status}" >&2; exit 2 ;;
esac

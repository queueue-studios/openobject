#!/usr/bin/env bash
# OpenObject kiosk launcher (HANDOFF §6).
#
# Runs inside the openobject-kiosk systemd unit. It (1) makes sure the Wayland runtime dir is
# set, (2) waits for the player to answer /healthz so the browser never opens on a dead port,
# then (3) hands off to `cage`, the Wayland kiosk compositor, which runs Chromium fullscreen.
set -euo pipefail

# logind normally sets this for the PAM session; default it just in case.
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_RUNTIME_DIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HEALTH_URL="${OO_HEALTH_URL:-http://localhost/healthz}"

# Wait for the player (up to ~60s). The page self-heals afterward regardless, so this only
# avoids the initial "can't reach the server" flash on a cold boot.
for _ in $(seq 1 60); do
  if curl -fsS -o /dev/null --max-time 2 "$HEALTH_URL"; then
    break
  fi
  sleep 1
done

# Hide the mouse pointer on the kiosk. cage takes its pointer from the cursor theme named
# "default" and ignores XCURSOR_THEME (confirmed at the bench), so expose our transparent
# cursors under that name: a "default" symlink to the shipped "blank" theme, rebuilt each start
# so it self-heals and a fresh install picks it up. Never fatal: a cursor glitch must not stop
# the kiosk. (The display's `cursor: none` only takes over once the pointer first moves.)
{ rm -rf "$HERE/cursors/default" && ln -s blank "$HERE/cursors/default"; } || true
export XCURSOR_PATH="$HERE/cursors"
export XCURSOR_THEME=default
export XCURSOR_SIZE=24

# cage runs a single client fullscreen and exits when it exits (systemd then relaunches us).
# -s allows VT switching, so Ctrl+Alt+F2 reaches a Debian console for servicing (on the bench
# keyboard the top-row keys are media keys, so in practice it is Ctrl+Alt+Fn+F2). Without -s cage
# locks the VT and there is no way off the kiosk with a keyboard. Physical access only.
exec cage -s -- "$HERE/chromium-kiosk.sh"

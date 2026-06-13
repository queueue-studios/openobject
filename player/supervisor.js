'use strict';

// OpenObject supervisor — the Phase-1 restart mechanism for self-update (HANDOFF §15).
//
// A tiny, dependency-free launcher. It runs the player (`node server.js`) and relaunches it
// when the player asks for a restart after a self-update — which the player signals by
// exiting with RESTART_CODE. That is what makes the whole update flow browser-driven with
// zero hardware access: the player stops to swap in new code, and this brings it right back
// up, on its own.
//
//   • A clean exit (0) or a Ctrl-C / termination passes through — the supervisor stops too.
//   • ONLY the explicit restart code relaunches. A crash is NOT auto-restarted in Phase 1,
//     so bugs surface during development rather than hiding in a restart loop.
//
// Phase 2 swaps this for a systemd unit (Restart=always) on the device — the player side is
// identical (it still just exits to restart). This file is intentionally minimal because a
// running supervisor keeps THIS copy until a full restart; it should rarely need to change.
//
// Run it with `npm start`. For quick development without the supervisor, `npm run start:direct`
// runs the server alone (self-update then asks you to restart by hand instead of auto-relaunching).

const path = require('path');
const { spawn } = require('node:child_process');

const RESTART_CODE = require('./src/restart-code');
const SERVER = path.join(__dirname, 'server.js');

let child = null;
let stopping = false;

function start() {
  // OO_SUPERVISED tells the server an auto-relaunch is available, so self-update may exit to
  // restart. Without it (start:direct), the server keeps running and asks for a manual restart.
  child = spawn(process.execPath, [SERVER], {
    stdio: 'inherit',
    env: { ...process.env, OO_SUPERVISED: '1' },
  });

  child.on('exit', (code, signal) => {
    if (stopping) return;
    if (code === RESTART_CODE) {
      console.log('[supervisor] player requested restart — relaunching…');
      start();
      return;
    }
    const note = signal ? `signal ${signal}` : `code ${code}`;
    console.log(`[supervisor] player exited (${note}); supervisor stopping.`);
    process.exit(signal ? 1 : code ?? 0);
  });
}

// Forward Ctrl-C / termination to the child and stop cleanly — no relaunch.
for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    stopping = true;
    if (child) child.kill(sig);
    process.exit(0);
  });
}

console.log('[supervisor] starting OpenObject player…');
start();

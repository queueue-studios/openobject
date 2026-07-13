'use strict';

// A best-effort, machine-global single-instance CHECK (not a hard lock). On startup it notes whether
// another OpenObject server already appears to be running on this machine, so running more than one
// (a stray `npm start`, a leftover dev or preview server) shows up in the logs instead of silently
// breaking mDNS / openobject.local resolution (the failure behind the 2026-07-12 outage).
//
// It NEVER blocks startup and NEVER changes advertising: the frame is single-instance and must always
// come up and stay discoverable. Every operation is wrapped so a failure just means "no check".

const fs = require('fs');
const os = require('os');
const path = require('path');

// One fixed path per machine/user, deliberately NOT under the data dir, so separate instances with
// different data dirs still see each other. os.tmpdir() is /tmp on the frame, the per-user temp on a Mac.
const LOCK_PATH = path.join(os.tmpdir(), 'openobject.lock');

// Is a PID currently alive? kill(pid, 0) sends no signal; it throws ESRCH once the process is gone.
// EPERM means it exists but we may not signal it, which still counts as alive.
function pidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try { process.kill(pid, 0); return true; }
  catch (e) { return !!(e && e.code === 'EPERM'); }
}

// Return the OTHER live instance ({ pid, port }) if one appears to be running, else null. Always
// (re)writes our own marker so the most recent instance owns the file. Fail-open: any error yields null.
function checkAndClaim({ port } = {}) {
  let other = null;
  try {
    const prev = JSON.parse(fs.readFileSync(LOCK_PATH, 'utf8'));
    if (prev && prev.pid !== process.pid && pidAlive(prev.pid)) {
      other = { pid: prev.pid, port: prev.port };
    }
  } catch { /* no file, unreadable, or garbage: nothing to report, we (over)write below */ }
  try {
    fs.writeFileSync(LOCK_PATH, JSON.stringify({ pid: process.pid, port: port || null, at: Date.now() }));
  } catch { /* best-effort */ }
  return other;
}

// Remove our marker on a clean exit. A stale file left by a crash is harmless (pidAlive filters it on
// the next start), so this is only tidiness.
function release() {
  try {
    const prev = JSON.parse(fs.readFileSync(LOCK_PATH, 'utf8'));
    if (prev && prev.pid === process.pid) fs.unlinkSync(LOCK_PATH);
  } catch { /* ignore */ }
}

module.exports = { checkAndClaim, release, LOCK_PATH };

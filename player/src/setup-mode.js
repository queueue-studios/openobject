// Wi-Fi setup mode, the player's half (HANDOFF §11, roadmap E8).
//
// The frame raises its own network when it cannot reach a known one; that part is
// installer/net/oo-setup-mode.sh, driven by a systemd timer and entirely independent of this
// process. This module is what the OWNER touches: it reports whether setup mode is on, scans for
// networks to offer, and applies the one they pick.
//
// Frame-only by construction: everything here runs `nmcli`, so on a Mac Host (no nmcli, no flag
// file) isOn() is false and the routes never engage.
const { execFile } = require('node:child_process');
const fs = require('fs');
const path = require('path');

// Overridable so the page and the screen can be exercised on a dev machine, where /run and nmcli do
// not exist. The frame never sets it, so the real path is the only one that matters in production.
const FLAG = process.env.OO_SETUP_FLAG || '/run/openobject/setup-mode';
const SCRIPT = path.join(__dirname, '..', '..', 'installer', 'net', 'oo-setup-mode.sh');

// Every nmcli call is bounded: a hung network tool must never wedge a control-panel request.
function run(cmd, args, timeout = 20000) {
  return new Promise((resolve) => {
    execFile(cmd, args, { timeout, encoding: 'utf8' }, (err, stdout, stderr) => {
      resolve({ ok: !err, stdout: stdout || '', stderr: stderr || (err && err.message) || '' });
    });
  });
}

function isOn() {
  try { return fs.existsSync(FLAG); } catch { return false; }
}

// The networks to offer, best signal first. Deduped by name, because the same network shows up once
// per band and per access point and the owner should see one entry, not five.
// A radio hosting an access point CANNOT scan, so while setup mode is on there is nothing to ask:
// oo-setup-mode.sh takes a scan just before it raises the AP and leaves it here. Falling back to a
// live scan keeps this useful off the frame and before the AP exists.
const NETS = process.env.OO_SETUP_NETS || '/run/openobject/networks';

async function scan() {
  let out = '';
  try { if (isOn() && fs.existsSync(NETS)) out = fs.readFileSync(NETS, 'utf8'); } catch { /* fall through */ }
  if (!out) {
    const r = await run('nmcli', ['-t', '-f', 'SSID,SIGNAL,SECURITY', 'device', 'wifi', 'list', '--rescan', 'yes'], 25000);
    if (!r.ok) return [];
    out = r.stdout;
  }
  const best = new Map();
  for (const line of out.split('\n')) {
    if (!line.trim()) continue;
    // nmcli -t escapes colons inside fields as '\:', so split on unescaped colons only.
    const parts = line.split(/(?<!\\):/).map((s) => s.replace(/\\:/g, ':'));
    const ssid = (parts[0] || '').trim();
    const signal = parseInt(parts[1], 10) || 0;
    const security = (parts[2] || '').trim();
    if (!ssid) continue;                       // hidden networks have no name to show; typed entry covers them
    if (ssid === (process.env.OO_AP_SSID || 'OpenObject-Setup')) continue;   // never offer our own AP
    const prev = best.get(ssid);
    if (!prev || signal > prev.signal) best.set(ssid, { ssid, signal, open: security === '' || security === '--' });
  }
  return [...best.values()].sort((a, b) => b.signal - a.signal);
}

// Save the chosen network and switch to it.
//
// Ordering matters and is the whole trick: the caller must have already answered the phone, because
// the moment the frame leaves its own AP the phone loses contact with it (§11). So this runs
// detached from the request: drop the AP, bring the new profile up, and if that fails, put the AP
// back so the owner gets another go rather than a frame that is simply gone.
//
// Old credentials are never deleted (§11): each network gets its own profile, so a router that
// comes back later still reconnects on its own.
async function applyLater(ssid, psk) {
  const conName = `oo-${ssid}`.slice(0, 60);
  await run('nmcli', ['connection', 'delete', conName], 10000);   // only ever OUR profile for this SSID
  const add = ['connection', 'add', 'type', 'wifi', 'con-name', conName, 'ssid', ssid,
               'connection.autoconnect', 'yes'];
  const r = await run('nmcli', add);
  if (!r.ok) return { ok: false, error: 'could not save the network' };
  if (psk) {
    const sec = await run('nmcli', ['connection', 'modify', conName,
      'wifi-sec.key-mgmt', 'wpa-psk', 'wifi-sec.psk', psk]);
    if (!sec.ok) return { ok: false, error: 'could not save the password' };
  }

  await run('sh', [SCRIPT, 'stop'], 20000);            // leave the AP: the phone drops here, by design
  const up = await run('nmcli', ['connection', 'up', conName], 45000);
  if (up.ok) return { ok: true };

  // Failed to join. Delete the bad profile so it cannot poison later autoconnects, and raise the AP
  // again so the owner can retry from the same screen rather than being stranded.
  await run('nmcli', ['connection', 'delete', conName], 10000);
  await run('sh', [SCRIPT, 'start'], 25000);
  return { ok: false, error: 'could not join that network' };
}

// What the panel should tell the owner to look for. Kept beside the AP itself so the screen can
// never advertise a network name or address that differs from the one actually being broadcast; the
// defaults match installer/net/oo-setup-mode.sh.
function apInfo() {
  return {
    ssid: process.env.OO_AP_SSID || 'OpenObject-Setup',
    password: process.env.OO_AP_PSK || 'openobject',
    address: (process.env.OO_AP_ADDR || '192.168.4.1/24').split('/')[0],
  };
}

module.exports = { isOn, scan, applyLater, apInfo, FLAG };

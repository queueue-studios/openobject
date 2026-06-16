'use strict';

// OpenObject player — web server.
//
// Serves the player's web surfaces from the player itself (HANDOFF §5):
//   • the control panel (/)        — upload, library, rotation settings, pin
//   • the display page  (/display) — the edge-to-edge kiosk stage Chromium points at
// No build step: the front-end is plain static files (HANDOFF §5).

const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const { execFile } = require('node:child_process');
const express = require('express');
const multer = require('multer');

const db = require('./src/db');
const { classify } = require('./src/formats');
const updater = require('./src/updater');
const RESTART_CODE = require('./src/restart-code');

// Set by the supervisor (HANDOFF §15). When supervised, the player may exit to auto-relaunch
// after a self-update; run directly (start:direct) it asks for a manual restart instead.
const SUPERVISED = process.env.OO_SUPERVISED === '1';

// A fresh id per process start. /healthz reports it so the control panel can confirm a restart
// happened — even a plain Restart, where the version/commit is unchanged (HANDOFF §10).
const BOOT_ID = crypto.randomBytes(4).toString('hex');

// Express 4 doesn't catch errors thrown from async handlers — wrap them so a rejected promise
// becomes a clean 500 instead of an unhandled rejection.
const ah = (fn) => (req, res) => fn(req, res).catch((err) => {
  console.error(err);
  if (!res.headersSent) res.status(500).json({ error: err.message });
});

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '0.0.0.0'; // reachable on the LAN (open it from a phone too)

// The repo checkout is the deployment unit (HANDOFF §15) — brand assets live at its root.
const REPO_ROOT = path.resolve(__dirname, '..');
const PUBLIC_DIR = path.join(__dirname, 'public');
const ASSETS_DIR = path.join(REPO_ROOT, 'assets');

// Rotation defaults (HANDOFF §7, §12): one global equal-time duration; order mode.
const DEFAULT_DURATION_MS = 8000;
const DEFAULT_MODE = 'sequence';
const MODES = new Set(['sequence', 'shuffle']);
const FITS = new Set(['fit', 'fill']);

// Sleep hours (HANDOFF §13): up to two daily windows, each independently enabled; the panel
// blanks to the dimmed mark while inside an enabled window (or while manually blanked). Off
// by default. Times are stored 24h "HH:MM"; the control panel shows them on a 12h clock.
const DEFAULT_SLEEP_RANGES = [
  { enabled: false, start: '22:00', end: '07:00' },
  { enabled: false, start: '09:00', end: '17:00' },
];
const HHMM = /^([01]\d|2[0-3]):([0-5]\d)$/;

db.initDb(); // ensure the SQLite store + uploads dir exist before serving

const app = express();
app.disable('x-powered-by');

// Content-Security-Policy: defense-in-depth for the control panel. Scripts and styles are
// external same-origin files and media is served from /uploads and /assets, so a strict
// policy costs nothing here and blocks injected inline script (e.g. via an uploaded filename).
app.use((_req, res, next) => {
  res.setHeader('Content-Security-Policy',
    "default-src 'self'; img-src 'self' data:; media-src 'self'; script-src 'self'; " +
    "style-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'");
  next();
});

app.use(express.json());

// Static front-end, brand assets, and the uploaded art itself.
app.use(express.static(PUBLIC_DIR));
app.use('/assets', express.static(ASSETS_DIR));
app.use('/uploads', express.static(db.UPLOADS_DIR));

// ── Optional control-panel password (HANDOFF §10) ───────────────────
// OFF BY DEFAULT: with no password set, authRequired() is false and authGate is a no-op, so the
// panel behaves exactly like an open-on-LAN frame, zero friction. When the owner sets a password
// (Settings), the control surface and every mutating API require a session; the kiosk surface
// stays open so the display and Chromium never need a credential. Stateless HMAC-signed cookie,
// no session store and no new dependency (built-in crypto only), in keeping with revivability.
const SESSION_COOKIE = 'oo_session';
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000; // 30 days
const SESSION_OPTS = { httpOnly: true, sameSite: 'lax', maxAge: SESSION_TTL_MS, path: '/' };

const authRequired = () => !!db.getSetting('auth_password_hash', '');

// One server secret signs session cookies; rotating it (which we do on every password set/clear)
// invalidates all existing sessions. Generated lazily on first use.
function authSecret() {
  let s = db.getSetting('auth_secret', '');
  if (!s) { s = crypto.randomBytes(32).toString('hex'); db.setSetting('auth_secret', s); }
  return s;
}
function setPassword(password) {
  const salt = crypto.randomBytes(16);
  const hash = crypto.scryptSync(String(password), salt, 64);
  db.setSetting('auth_password_hash', `${salt.toString('hex')}:${hash.toString('hex')}`);
  db.setSetting('auth_secret', crypto.randomBytes(32).toString('hex')); // log out old sessions
}
function clearPassword() {
  db.setSetting('auth_password_hash', '');
  db.setSetting('auth_secret', crypto.randomBytes(32).toString('hex')); // invalidate sessions
}
function verifyPassword(password) {
  const stored = db.getSetting('auth_password_hash', '');
  const [saltHex, hashHex] = (stored || '').split(':');
  if (!saltHex || !hashHex) return false;
  const expected = Buffer.from(hashHex, 'hex');
  const actual = crypto.scryptSync(String(password), Buffer.from(saltHex, 'hex'), expected.length);
  return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
}
// Signed session token "<expiry>.<hmac>": verified without any server-side store.
function makeToken() {
  const exp = String(Date.now() + SESSION_TTL_MS);
  return `${exp}.${crypto.createHmac('sha256', authSecret()).update(exp).digest('hex')}`;
}
function validToken(tok) {
  const i = tok ? tok.indexOf('.') : -1;
  if (i < 0) return false;
  const exp = tok.slice(0, i), sig = tok.slice(i + 1);
  if (!/^\d+$/.test(exp) || Number(exp) < Date.now()) return false;
  const want = crypto.createHmac('sha256', authSecret()).update(exp).digest('hex');
  return sig.length === want.length && crypto.timingSafeEqual(Buffer.from(sig), Buffer.from(want));
}
function cookies(req) {
  const out = {};
  (req.headers.cookie || '').split(';').forEach((c) => {
    const i = c.indexOf('=');
    if (i > 0) out[c.slice(0, i).trim()] = decodeURIComponent(c.slice(i + 1).trim());
  });
  return out;
}
const isAuthed = (req) => validToken(cookies(req)[SESSION_COOKIE]);

// Gate: when a password is set, every /api/* call needs a session EXCEPT the kiosk read
// (/api/display), the liveness probe (/healthz, not under /api/), and the auth endpoints needed
// to log in. Pages, brand assets, and uploaded media stay open so the kiosk and the login screen
// work with no credential. With no password set this returns immediately (open frame).
const AUTH_OPEN = new Set(['/api/display', '/api/auth/status', '/api/auth/login', '/api/auth/logout']);
function authGate(req, res, next) {
  if (!authRequired()) return next();
  if (!req.path.startsWith('/api/')) return next();
  if (AUTH_OPEN.has(req.path)) return next();
  if (isAuthed(req)) return next();
  return res.status(401).json({ error: 'auth required' });
}
app.use(authGate);

// Auth status drives the control panel: whether a password is required and whether this browser
// is logged in. Always open (the panel calls it on load to decide if it must show the login box).
app.get('/api/auth/status', (req, res) => {
  res.json({ required: authRequired(), authed: !authRequired() || isAuthed(req) });
});
app.post('/api/auth/login', (req, res) => {
  if (!authRequired()) return res.json({ ok: true, authed: true }); // nothing to log into
  if (!verifyPassword((req.body || {}).password)) return res.status(401).json({ error: 'Wrong password.' });
  res.cookie(SESSION_COOKIE, makeToken(), SESSION_OPTS);
  res.json({ ok: true, authed: true });
});
app.post('/api/auth/logout', (_req, res) => {
  res.clearCookie(SESSION_COOKIE, { path: '/' });
  res.json({ ok: true });
});
// Set or change the password. Turning it ON the first time works because the gate is open while
// no password exists; once set, this route is gated (it lives under /api/), so a change needs a
// session. We keep the setter logged in with a fresh cookie.
app.put('/api/auth/password', (req, res) => {
  const password = (req.body || {}).password;
  if (typeof password !== 'string' || password.length < 4) {
    return res.status(400).json({ error: 'Password must be at least 4 characters.' });
  }
  setPassword(password);
  res.cookie(SESSION_COOKIE, makeToken(), SESSION_OPTS);
  res.json({ ok: true, required: true, authed: true });
});
// Turn protection off (gated: only a logged-in session reaches here).
app.delete('/api/auth/password', (_req, res) => {
  clearPassword();
  res.clearCookie(SESSION_COOKIE, { path: '/' });
  res.json({ ok: true, required: false });
});

// ── Uploads — the default web-upload source (HANDOFF §8) ─────────────
// Files are stored byte-for-byte. Unsupported types are skipped silently (§6): the
// filter drops them (never written) and records the name so the response can report it.
const storage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, db.UPLOADS_DIR),
  filename: (_req, file, cb) => {
    const info = classify(file.originalname); // non-null: fileFilter already accepted it
    const stamp = Date.now().toString(36) + '-' + crypto.randomBytes(4).toString('hex');
    cb(null, `${stamp}.${info.format}`);
  },
});
// Per-upload limits so a LAN client cannot fill the disk in one shot (HANDOFF §8 hardening).
// Defaults are roomy for real art (large video included) and overridable via env at the bench.
const MAX_UPLOAD_MB = Number(process.env.OO_MAX_UPLOAD_MB) || 512;
const MAX_UPLOAD_FILES = Number(process.env.OO_MAX_UPLOAD_FILES) || 50;
const upload = multer({
  storage,
  limits: { fileSize: MAX_UPLOAD_MB * 1024 * 1024, files: MAX_UPLOAD_FILES },
  fileFilter: (req, file, cb) => {
    if (classify(file.originalname)) return cb(null, true);
    (req.skipped ||= []).push(file.originalname); // unsupported → skip, don't error
    cb(null, false);
  },
});

// Refuse uploads before the disk gets dangerously full, so the OS, the database, and the
// player stay responsive (HANDOFF §8 hardening). Pre-flight check on the uploads volume; if
// statfs is unavailable we do not block. Keep ~2 GB headroom by default (override via env).
const MIN_FREE_MB = Number(process.env.OO_MIN_FREE_MB) || 2048;
async function ensureDiskSpace(_req, res, next) {
  try {
    const st = await fs.promises.statfs(db.UPLOADS_DIR);
    const freeMB = (st.bavail * st.bsize) / (1024 * 1024);
    if (freeMB < MIN_FREE_MB) {
      return res.status(507).json({ error: 'Not enough free space on the frame. Delete some art and try again.' });
    }
  } catch { /* statfs unavailable: do not block uploads */ }
  next();
}

app.post('/api/upload', ensureDiskSpace, upload.array('files'), (req, res) => {
  const added = (req.files || []).map((f) => {
    const info = classify(f.originalname);
    return db.addLibraryItem({
      filename: f.filename,
      original_name: f.originalname,
      mime: info.mime,
      format: info.format,
      kind: info.kind,
      bytes: f.size,
    });
  });
  res.json({ added, skipped: req.skipped || [] });
});

// ── Library API ─────────────────────────────────────────────────────
app.get('/api/library', (_req, res) => {
  res.json(db.listLibrary());
});

// Per-clip Fit/Fill (§6) and Rotation membership (§7). Either or both may be sent.
app.patch('/api/library/:id', (req, res) => {
  const id = Number(req.params.id);
  const { fit, inRotation } = req.body || {};
  if (fit === undefined && inRotation === undefined) {
    return res.status(400).json({ error: 'nothing to update (fit and/or inRotation)' });
  }
  if (fit !== undefined && !FITS.has(fit)) {
    return res.status(400).json({ error: 'fit must be "fit" or "fill"' });
  }
  if (inRotation !== undefined && typeof inRotation !== 'boolean') {
    return res.status(400).json({ error: 'inRotation must be a boolean' });
  }
  if (!db.getLibraryItem(id)) return res.status(404).json({ error: 'not found' });
  if (fit !== undefined) db.setLibraryFit(id, fit);
  if (inRotation !== undefined) db.setLibraryRotation(id, inRotation);
  res.json(db.getLibraryItem(id));
});

app.delete('/api/library/:id', (req, res) => {
  const row = db.deleteLibraryItem(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'not found' });
  if (Number(db.getSetting('pinned_id', '')) === row.id) db.setSetting('pinned_id', ''); // drop a stale pin
  fs.rm(path.join(db.UPLOADS_DIR, row.filename), { force: true }, () => {}); // best-effort file removal
  res.json({ deleted: row.id });
});

// ── Rotation curation (HANDOFF §7) — membership rides on the library row; order is its own call ──
app.get('/api/rotation', (_req, res) => {
  res.json(db.listRotation()); // curated members in order (not pin-collapsed; that's display-only)
});

app.put('/api/rotation/order', (req, res) => {
  const order = req.body && req.body.order;
  if (!Array.isArray(order) || order.some((n) => !Number.isFinite(Number(n)))) {
    return res.status(400).json({ error: 'order must be an array of library ids' });
  }
  res.json(db.reorderRotation(order));
});

// ── Rotation settings (global, equal-time) + Pin + Sleep hours ──────
const toMinutes = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
function inWindow(nowMin, startMin, endMin) {
  if (startMin === endMin) return false;        // zero-length window = off
  return startMin < endMin
    ? nowMin >= startMin && nowMin < endMin      // same-day window
    : nowMin >= startMin || nowMin < endMin;     // wraps past midnight (overnight)
}
function isAsleep(settings, now = new Date()) {
  if (settings.manualBlank) return true;         // manual Blank overrides the schedule (HANDOFF §13)
  const nowMin = now.getHours() * 60 + now.getMinutes();
  return settings.sleepRanges.some((r) => r.enabled && inWindow(nowMin, toMinutes(r.start), toMinutes(r.end)));
}
function readSleepRanges() {
  try {
    const v = JSON.parse(db.getSetting('sleep_ranges', ''));
    if (Array.isArray(v)) return v.map((r) => ({ enabled: !!r.enabled, start: String(r.start), end: String(r.end) }));
  } catch { /* not set yet / malformed — use defaults */ }
  return DEFAULT_SLEEP_RANGES.map((r) => ({ ...r }));
}

function currentSettings() {
  const pin = db.getSetting('pinned_id', '');
  return {
    durationMs: Number(db.getSetting('duration_ms', DEFAULT_DURATION_MS)) || DEFAULT_DURATION_MS,
    mode: db.getSetting('rotation_mode', DEFAULT_MODE),
    pinnedId: pin ? Number(pin) : null, // one piece held permanently (HANDOFF §7), or null
    sleepRanges: readSleepRanges(),     // up to two daily blank windows (HANDOFF §13)
    manualBlank: db.getSetting('manual_blank', '') === '1', // instant "Blank panel" override
  };
}

app.get('/api/settings', (_req, res) => res.json(currentSettings()));

app.put('/api/settings', (req, res) => {
  const { durationMs, mode, sleepRanges, manualBlank } = req.body || {};
  if (durationMs !== undefined) {
    const ms = Number(durationMs);
    if (!Number.isFinite(ms) || ms < 1000) return res.status(400).json({ error: 'durationMs must be >= 1000' });
    db.setSetting('duration_ms', Math.round(ms));
  }
  if (mode !== undefined) {
    if (!MODES.has(mode)) return res.status(400).json({ error: 'mode must be sequence|shuffle' });
    db.setSetting('rotation_mode', mode);
  }
  if (sleepRanges !== undefined) {
    const ok =
      Array.isArray(sleepRanges) &&
      sleepRanges.length <= 2 &&
      sleepRanges.every((r) => r && typeof r.enabled === 'boolean' && HHMM.test(r.start) && HHMM.test(r.end));
    if (!ok) return res.status(400).json({ error: 'sleepRanges must be up to two {enabled, start:"HH:MM", end:"HH:MM"}' });
    db.setSetting('sleep_ranges', JSON.stringify(sleepRanges.map((r) => ({ enabled: r.enabled, start: r.start, end: r.end }))));
  }
  if (manualBlank !== undefined) {
    if (typeof manualBlank !== 'boolean') return res.status(400).json({ error: 'manualBlank must be a boolean' });
    db.setSetting('manual_blank', manualBlank ? '1' : '');
  }
  res.json(currentSettings());
});

// Pin one piece (hold it on the panel permanently); DELETE to unpin and resume rotation.
app.put('/api/pin/:id', (req, res) => {
  const id = Number(req.params.id);
  if (!db.getLibraryItem(id)) return res.status(404).json({ error: 'not found' });
  db.setSetting('pinned_id', id);
  res.json(currentSettings());
});
app.delete('/api/pin', (_req, res) => {
  db.setSetting('pinned_id', '');
  res.json(currentSettings());
});

// What the display plays: while asleep (a sleep window or manual Blank, §13) it serves
// `asleep:true` and the display shows the dimmed mark. Otherwise a pinned piece overrides
// everything — held permanently even if not in the Rotation (§7) — else the Rotation in order.
app.get('/api/display', (_req, res) => {
  const settings = currentSettings();
  const pinned = settings.pinnedId != null ? db.getLibraryItem(settings.pinnedId) : null;
  res.json({
    items: pinned ? [pinned] : db.listRotation(),
    durationMs: settings.durationMs,
    mode: settings.mode,
    pinnedId: settings.pinnedId,
    asleep: isAsleep(settings),
  });
});

// ── Self-update from GitHub (HANDOFF §15) ───────────────────────────
// Owner-initiated, never automatic, never in the playback path. All git logic lives in
// src/updater.js; these routes are the thin control-panel surface.

// Instant status for page load — no network, so it's offline-safe and never blocks.
app.get('/api/update', ah(async (_req, res) => {
  res.json({ ...(await updater.localStatus()), supervised: SUPERVISED });
}));

// Check for updates: fetch + compare to the channel's target. A network failure → offline.
app.post('/api/update/check', ah(async (_req, res) => {
  res.json(await updater.check());
}));

// Update channel: track `main` (default) or tagged releases only (HANDOFF §12, §15).
app.put('/api/update/channel', ah(async (req, res) => {
  try {
    updater.setChannel((req.body || {}).channel);
  } catch (e) {
    return res.status(400).json({ error: e.message });
  }
  res.json(await updater.localStatus());
}));

// Update & restart: fast-forward + (deps if changed), then — only if that succeeded and we're
// supervised — exit with the restart code so the supervisor relaunches us on the new code.
// Not supervised → we report `needsManualRestart` and keep running the old code until restarted.
app.post('/api/update/apply', ah(async (_req, res) => {
  const result = await updater.apply();
  const canRestart = result.ok && result.updated && (!result.depsChanged || result.installed);
  const willRestart = canRestart && SUPERVISED;
  res.json({ ...result, restarting: willRestart, needsManualRestart: canRestart && !SUPERVISED });
  if (willRestart) setTimeout(() => process.exit(RESTART_CODE), 350); // let the response flush first
}));

// ── Power & network (HANDOFF §10, §11) — owner-initiated, never in the playback path ──
// On macOS (Phase 1) only the app-level Restart can truly act; Shut down and Wi-Fi onboarding
// are hardware actions and ship as visible-but-inert stubs until the device exists.

// IPv4 LAN addresses, so the panel can show "reach me from your phone at …" (a real help today).
function lanAddresses() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const ni of list || []) if (ni.family === 'IPv4' && !ni.internal) out.push(ni.address);
  }
  return out;
}

app.get('/api/system', (_req, res) => {
  res.json({
    supervised: SUPERVISED,
    port: PORT,
    mdns: 'openobject.local',  // resolves on the installed frame (Phase 2 mDNS), not on the dev Mac
    addresses: lanAddresses(), // reachable now from another device on the same network
  });
});

// Restart the player (HANDOFF §10) — a real soft-restart via the supervisor (exit → relaunch),
// the same mechanism self-update uses. On the device (Phase 2) systemd performs the relaunch.
// Run un-supervised (start:direct) there's nothing to relaunch us, so we report that instead.
app.post('/api/system/restart', (_req, res) => {
  res.json({ ok: true, restarting: SUPERVISED, needsManualRestart: !SUPERVISED });
  if (SUPERVISED) setTimeout(() => process.exit(RESTART_CODE), 350); // let the response flush first
});

// Reboot / shut down the whole device (HANDOFF §17). Real on the installed Linux frame, where
// systemd carries it out; an inert stub anywhere else, so this can NEVER power off a dev Mac. The
// one-time polkit grant in installer/install.sh is what lets the unprivileged `openobject` user
// run these; without it logind refuses and we report that, leaving the frame untouched.
const IS_DEVICE = process.platform === 'linux';
function powerAction(verb, res) { // verb: 'reboot' | 'poweroff'
  const noun = verb === 'reboot' ? 'Reboot' : 'Shut down';
  if (!IS_DEVICE) {
    return res.json({ ok: false, stub: true, message: `${noun} only works on the installed frame; there is nothing to ${verb === 'reboot' ? 'reboot' : 'power off'} in this preview.` });
  }
  // systemctl returns 0 once the job is queued, then the box goes down, so a success reply may not
  // reach the panel (the connection drops). A fast non-zero is a real refusal (usually a missing
  // polkit grant), which we report so nothing looks hung. Either way we respond from the callback.
  execFile('systemctl', [verb], { timeout: 10000 }, (err, _stdout, stderr) => {
    if (err) return res.json({ ok: false, error: (stderr || err.message || `could not ${verb}`).toString().trim(), needsGrant: true });
    res.json({ ok: true, [verb === 'reboot' ? 'rebooting' : 'poweringOff']: true });
  });
}

app.post('/api/system/reboot', (_req, res) => powerAction('reboot', res));

// Shut down powers the frame off via `systemctl poweroff` (see powerAction above). With BIOS
// Auto-Power-On the unit returns when power is restored, so a true "off" is the wall outlet or a
// smart plug (HANDOFF §10, §17).
app.post('/api/system/shutdown', (_req, res) => powerAction('poweroff', res));

// ── Pages ───────────────────────────────────────────────────────────
// The kiosk display surface (HANDOFF §6). In Phase 2 Chromium boots straight to this.
app.get('/display', (_req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'display.html'));
});

// The control panel home (HANDOFF §5).
app.get('/', (_req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'control.html'));
});

// Liveness probe — also how the Phase-1 self-update flow confirms the player came back up
// after restarting itself: `commit` is this checkout's HEAD, so the control panel can tell a
// new version is live (HANDOFF §15).
app.get('/healthz', (_req, res) => {
  res.json({ ok: true, app: 'openobject', version: require('./package.json').version, commit: updater.cachedCommitSync(), boot: BOOT_ID });
});

// JSON error responses for the API (e.g. multer rejections) instead of HTML stack traces.
app.use((err, _req, res, _next) => {
  console.error(err);
  if (err instanceof multer.MulterError) {
    if (err.code === 'LIMIT_FILE_SIZE') {
      return res.status(413).json({ error: `That file is too large. The limit is ${MAX_UPLOAD_MB} MB per file.` });
    }
    if (err.code === 'LIMIT_FILE_COUNT') {
      return res.status(400).json({ error: `Too many files at once. Please add up to ${MAX_UPLOAD_FILES} at a time.` });
    }
    return res.status(400).json({ error: err.message });
  }
  res.status(400).json({ error: err.message });
});

// Cache the running commit for /healthz (HANDOFF §15) before serving; never block boot on it.
updater.refreshCommitCache().finally(() => {
  app.listen(PORT, HOST, () => {
    console.log(`OpenObject player listening on http://localhost:${PORT}`);
    console.log(`  • control  →  http://localhost:${PORT}/`);
    console.log(`  • display  →  http://localhost:${PORT}/display`);
    console.log(`  • version  →  ${require('./package.json').version} (commit ${updater.cachedCommitSync() || '—'})${SUPERVISED ? ' · supervised' : ''}`);
  });
});

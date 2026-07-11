'use strict';

// OpenObject player — web server. This process is the HOST role (see below).
//
// Three roles, one engine (HANDOFF §20, 2026-07-01; MAC-APP-PLAN §2). OpenObject has a single
// shared engine (this player/) that runs byte-for-byte the same on the XXL frame and on a Mac;
// what differs between deployments is only the packaging shell around it. The engine's behavior
// splits into three roles:
//   • HOST    — owns the Library + Rotation, serves the API and /display. THIS server. The XXL is
//               always a Host; a Mac can optionally be one. Binds the LAN (0.0.0.0) so any Display
//               or Control client on the network can reach it.
//   • DISPLAY — renders exactly one Host's /display, full screen, zero chrome. The XXL kiosk, a Mac
//               Chrome window, and a future Apple TV are each a Display. It targets whichever Host
//               served its page (display.js fetches same-origin), so "which Host" is chosen by the
//               URL the Display is pointed at, not by anything in here.
//   • CONTROL — the web control panel (/). Already Host-agnostic: any browser on the network can
//               drive any Host.
// Naming the roles is vocabulary only; the code already works this way. It is the seam the Mac app
// and the future tvOS client both fall out of (one Host discoverable on the LAN, many Displays).
//
// Serves the player's web surfaces from the player itself (HANDOFF §5):
//   • the control panel (/)        — Control role: upload, library, rotation settings, pin
//   • the display page  (/display) — Display role: the edge-to-edge kiosk stage Chromium points at
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
const collections = require('./src/collections');
const folders = require('./src/folders');
const seed = require('./src/seed');
const identity = require('./src/identity');
const discovery = require('./src/discovery');
const remoteFolders = require('./src/remote-folders');
const folderCacheMod = require('./src/folder-cache');
const RESTART_CODE = require('./src/restart-code');

// Set by the supervisor (HANDOFF §15). When supervised, the player may exit to auto-relaunch
// after a self-update; run directly (start:direct) it asks for a manual restart instead.
const SUPERVISED = process.env.OO_SUPERVISED === '1';

// A fresh id per process start. /healthz reports it so the control panel can confirm a restart
// happened — even a plain Restart, where the version/commit is unchanged (HANDOFF §10).
const BOOT_ID = crypto.randomBytes(4).toString('hex');

// Retro Arcade — the hidden self-playing "attract mode" demo (an easter egg). This on/off flag is
// RUNTIME-ONLY: it is never written to the store, so a restart, reboot, or crash always wakes the
// frame to art, never into the demo. The control panel flips it (a secret key sequence turns it on,
// Return to Art off); the display reads it from /api/display and swaps the rotation for the canvas.
// Homage notice: a trivial, non-playable, era-styled homage; no specific game or brand is reproduced
// (full notice in player/public/arcade.js).
let retroArcade = false;

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

// Phase B (frame): a Display client's live view of folders served by OTHER Hosts over the LAN (§17).
// `discoveryBrowser` is populated on the frame in the listen block far below; `remote` reads it
// lazily, so the current set of Hosts is always reflected. Both are inert on a standalone Host.
let discoveryBrowser = null;
const remote = remoteFolders.create({ hostsProvider: () => (discoveryBrowser ? discoveryBrowser.list() : []) });
// The frame's ephemeral cache for a remote folder's media (§17 Phase B). Wiped on construction (engine
// start), on switching/leaving folders, and by a manual Clear. Inert on a standalone Host (never fed).
const folderCache = folderCacheMod.create({
  dir: path.join(db.DATA_DIR, 'folder-cache'),
  resolveBase: async (hostId, folderId) => {
    const f = await remote.resolve(remoteFolders.makeRef(hostId, folderId));
    return f ? f.base : null;
  },
});
// Library grid sort: recent (default) | oldest | title | artist. recent/oldest/title are SQL orders in
// db.listLibrary; "artist" is resolved here (libraryByArtist) because a connected piece's artist lives in
// the registry, not the DB row. This set just validates the persisted choice (HANDOFF §7). Every order
// keeps the install sample anchored last.
const LIBRARY_SORTS = new Set([...Object.keys(db.LIBRARY_SORTS), 'artist']);

// Library view filter (HANDOFF §7): which subset of the grid to show. A persisted view setting like
// the sort, but applied in the browser (the filter is trivial; it never touches the /api/library query),
// so the Library tab count stays the whole library. 'all' shows everything; 'rotation' shows only pieces
// currently in the rotation, a one-click declutter the owner can reverse without deleting anything.
const LIBRARY_FILTERS = new Set(['all', 'rotation']);

// Sleep Schedule (HANDOFF §13): up to three day-aware windows, each with its own days of the
// week; the panel blanks to the dimmed mark while inside an active window (or while manually
// blanked). Off by default (no windows). Times are stored 24h "HH:MM" with days as 0-6 (0=Sun);
// the control panel shows them on a 12h clock. An overnight window is anchored to the day it
// begins, so its evening half counts as that day and its after-midnight half as the day before.
const HHMM = /^([01]\d|2[0-3]):([0-5]\d)$/;
const SLEEP_DAYS_ALL = [0, 1, 2, 3, 4, 5, 6];

db.initDb(); // ensure the SQLite store + uploads dir exist before serving
seed.seedSampleIfNeeded(); // first run: copy the shipped sample piece into the Library (HANDOFF §20)

const app = express();
app.disable('x-powered-by');

// Content-Security-Policy: defense-in-depth for the control panel. Scripts and styles are
// external same-origin files and media is served from /uploads and /assets, so a strict
// policy costs nothing here and blocks injected inline script (e.g. via an uploaded filename).
app.use((req, res, next) => {
  // Mirrored connected-art bundles under /collections get their own policy (below): vetted
  // third-party art needs inline script/handlers and must be frameable by the same-origin display.
  if (req.path.startsWith('/collections/')) return next();
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

// Folder Collection media (HANDOFF §17, Phase A): stream a file straight from a registered local
// folder, in place (never copied into the Library). Public like /uploads — the kiosk display fetches
// it, and it stays reachable with a control-panel password set (kiosk content). The path is locked
// down in folders.resolveMedia (single segment, compliant, directly inside the folder), with
// res.sendFile(root) as the containment backstop; range requests (video scrubbing) fall out of sendFile.
app.get('/folder-media/:id/:file', ah(async (req, res) => {
  // Frame (§17 Phase B): :id is a remote folder key (<hostId>.<folderId>), served from the ephemeral
  // cache, fetching from the Mac on a miss. A cap/floor overflow is proxy-streamed without caching.
  if (identity.deviceRole() === 'frame') {
    const hit = await folderCache.get(req.params.id, req.params.file);
    if (!hit) return res.status(404).end();
    if (hit.localPath) {
      return res.sendFile(path.basename(hit.localPath), { root: path.dirname(hit.localPath), dotfiles: 'deny' }, (err) => {
        if (err && !res.headersSent) res.status(404).end();
      });
    }
    let up;
    try { up = await fetch(hit.streamUrl, { signal: AbortSignal.timeout(20000) }); } catch { return res.status(504).end(); }
    if (!up || !up.ok || !up.body) return res.status(502).end();
    const ct = up.headers.get('content-type'); if (ct) res.setHeader('Content-Type', ct);
    const len = up.headers.get('content-length'); if (len) res.setHeader('Content-Length', len);
    return require('stream').Readable.fromWeb(up.body).pipe(res);
  }
  // Local Folder Collection (Phase A): stream straight from the registered folder.
  const folder = db.getFolderCollection(Number(req.params.id));
  if (!folder) return res.status(404).end();
  const hit = folders.resolveMedia(folder, req.params.file);
  if (!hit) return res.status(404).end();
  res.sendFile(hit.name, { root: hit.root, dotfiles: 'deny' }, (err) => {
    if (err && !res.headersSent) res.status(404).end();
  });
}));

// Mirrored connected-art bundles (src/collections.js). Served same-origin so the
// art runs and the display can frame it; locked to our own resources, just allowing the inline
// script/handlers these p5 sketches use. Stays open with a password set (it's kiosk content).
// connect-src includes data:/blob: because p5's loadImage() fetches images these sketches build in
// memory as data: URLs (e.g. Azulejo's print-sheet fold diagram, used only by its export menu).
// Without it that fetch is blocked: harmless to the displayed art, but it spams the console with a
// "Failed to fetch" on every load. No remote origins by default (no phoning home), with ONE narrow
// exception: a `liveRpc` collection (e.g. send/receive) reads live on-chain state to animate, so its
// own bundle path is allowed to connect to a single public Ethereum node (scoped per collection).
app.use('/collections', (req, res, next) => {
  const rpcOrigin = collections.liveRpcForPath(req.path); // non-null only for a liveRpc collection's path
  res.setHeader('Content-Security-Policy',
    "default-src 'self'; img-src 'self' data: blob:; media-src 'self' data: blob:; " +
    "script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; " +
    `connect-src 'self' data: blob:${rpcOrigin ? ' ' + rpcOrigin : ''}; ` +
    "object-src 'none'; base-uri 'none'; frame-ancestors 'self'");
  next();
}, express.static(collections.COLLECTIONS_DIR));

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
// /api/identity stays open: it exposes only what the Bonjour TXT records already broadcast
// unauthenticated (id, name, version, role), so a Host stays discoverable-by-name even behind a
// password. It carries nothing a password protects.
const AUTH_OPEN = new Set(['/api/display', '/api/identity', '/api/auth/status', '/api/auth/login', '/api/auth/logout']);
function authGate(req, res, next) {
  if (!authRequired()) return next();
  if (!req.path.startsWith('/api/')) return next();
  if (AUTH_OPEN.has(req.path)) return next();
  // Folder Collections shared to LAN Displays (§17 Phase B) are open and path-free, exactly like
  // /api/display and /folder-media: a frame reads them with no credential. The prefix covers the
  // per-folder /:id/items. They expose only names/counts and compliant filenames, never a path.
  if (req.path === '/api/shared-folders' || req.path.startsWith('/api/shared-folders/')) return next();
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
// "Artist" sort lives here, not in db.listLibrary, because a connected piece's artist is in the registry
// (src/collections.js), not the DB row. Effective artist = the row's own `artist` (uploads) or the
// collection's registry artist (connected), i.e. the name shown on the card. Order: the install sample
// last (the anchor every sort keeps), then credited pieces A to Z by artist, then the un-credited at the
// end (nulls last; HANDOFF §7), each group tiebroken by the displayed title. Built on the title-sorted list
// (sample already last, title/id tiebreak baked in) and re-sorted with a stable sort.
function libraryByArtist() {
  const effArtist = (r) => (r.kind === 'connected' ? (collections.bySlug(r.collection) || {}).artist : r.artist) || '';
  const effTitle = (r) => (r.title && r.title.trim() ? r.title : r.original_name) || '';
  const cmp = (a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' });
  return db.listLibrary('title').sort((x, y) => {
    const xS = (x.collection || '') === db.INSTALL_SAMPLE_COLLECTION;
    const yS = (y.collection || '') === db.INSTALL_SAMPLE_COLLECTION;
    if (xS !== yS) return xS ? 1 : -1;                  // install sample always last
    const xa = effArtist(x), ya = effArtist(y);
    if (!xa !== !ya) return xa ? -1 : 1;                // un-credited (blank) artist last
    return cmp(xa, ya) || cmp(effTitle(x), effTitle(y)); // by artist, then displayed title
  });
}

app.get('/api/library', (_req, res) => {
  const sort = db.getSetting('library_sort', db.DEFAULT_LIBRARY_SORT);
  res.json(sort === 'artist' ? libraryByArtist() : db.listLibrary(sort));
});

// Per-clip Fit/Fill (§6), Rotation membership (§7), and optional title/artist (§7). Any subset may be sent.
app.patch('/api/library/:id', (req, res) => {
  const id = Number(req.params.id);
  const { fit, inRotation, title, artist } = req.body || {};
  if (fit === undefined && inRotation === undefined && title === undefined && artist === undefined) {
    return res.status(400).json({ error: 'nothing to update (fit, inRotation, title, and/or artist)' });
  }
  if (fit !== undefined && !FITS.has(fit)) {
    return res.status(400).json({ error: 'fit must be "fit" or "fill"' });
  }
  if (inRotation !== undefined && typeof inRotation !== 'boolean') {
    return res.status(400).json({ error: 'inRotation must be a boolean' });
  }
  for (const [k, v] of [['title', title], ['artist', artist]]) {
    if (v === undefined) continue;
    if (typeof v !== 'string') return res.status(400).json({ error: `${k} must be a string` });
    if (v.length > 200) return res.status(400).json({ error: `${k} must be 200 characters or fewer` });
  }
  const row = db.getLibraryItem(id);
  if (!row) return res.status(404).json({ error: 'not found' });
  // Title/artist are owner-set metadata for uploaded pieces; connected pieces carry theirs from the
  // chain/registry (kept authoritative), so reject an attempt to override them.
  if ((title !== undefined || artist !== undefined) && row.kind === 'connected') {
    return res.status(400).json({ error: 'title and artist can only be set on uploaded pieces' });
  }
  if (fit !== undefined) db.setLibraryFit(id, fit);
  if (inRotation !== undefined) db.setLibraryRotation(id, inRotation);
  if (title !== undefined || artist !== undefined) db.setLibraryMeta(id, { title, artist });
  res.json(db.getLibraryItem(id));
});

app.delete('/api/library/:id', (req, res) => {
  const row = db.deleteLibraryItem(Number(req.params.id));
  if (!row) return res.status(404).json({ error: 'not found' });
  if (Number(db.getSetting('pinned_id', '')) === row.id) db.setSetting('pinned_id', ''); // drop a stale pin
  if (row.kind === 'connected') {
    // Drop this piece's cached thumbnail, then let removeBundle reclaim disk: a per-token bundle is
    // this piece's alone; a shared bundle is kept only until the collection's LAST piece is deleted.
    if (row.thumb && row.thumb.startsWith('/collections/')) {
      fs.rm(path.join(collections.COLLECTIONS_DIR, row.thumb.replace('/collections/', '')), { force: true }, () => {});
    }
    collections.removeBundle(row.collection, row.token_id);
  } else {
    fs.rm(path.join(db.UPLOADS_DIR, row.filename), { force: true }, () => {}); // best-effort file removal
  }
  res.json({ deleted: row.id });
});

// ── Connected collections (src/collections.js) ─────────
// The supported list is code; the owner curates which show (hide/unhide) and toggles animate.
app.get('/api/collections', (_req, res) => res.json(collections.list()));

app.patch('/api/collections/:slug', (req, res) => {
  const { hidden, animate, speed, choice, controls } = req.body || {};
  if (hidden === undefined && animate === undefined && speed === undefined && choice === undefined && controls === undefined) {
    return res.status(400).json({ error: 'nothing to update' });
  }
  if ((hidden !== undefined && typeof hidden !== 'boolean') || (animate !== undefined && typeof animate !== 'boolean')) {
    return res.status(400).json({ error: 'hidden/animate must be booleans' });
  }
  if (speed !== undefined && (typeof speed !== 'number' || !Number.isFinite(speed) || speed < 0 || speed > 10)) {
    return res.status(400).json({ error: 'speed must be a number from 0 to 10' });
  }
  const c = collections.bySlug(req.params.slug);
  if (!c) return res.status(404).json({ error: 'unknown collection' });
  // A choice control accepts only one of its declared option values (a collection without a choice
  // control accepts none).
  if (choice !== undefined) {
    const allowed = c.choice ? c.choice.options.map((o) => String(o.value)) : [];
    if (!allowed.includes(String(choice))) return res.status(400).json({ error: 'invalid choice' });
  }
  // A controls patch is a partial {key:value} over the collection's general controls model: each key must be a
  // declared control, a range value a number within [min,max], a select value one of its options.
  if (controls !== undefined) {
    if (typeof controls !== 'object' || controls === null || Array.isArray(controls)) {
      return res.status(400).json({ error: 'controls must be an object' });
    }
    const defs = Array.isArray(c.controls) ? c.controls : [];
    for (const [k, v] of Object.entries(controls)) {
      const def = defs.find((d) => d.key === k);
      if (!def) return res.status(400).json({ error: 'unknown control: ' + k });
      if (def.type === 'range') {
        if (typeof v !== 'number' || !Number.isFinite(v) || v < def.min || v > def.max) {
          return res.status(400).json({ error: `${def.label} must be a number from ${def.min} to ${def.max}` });
        }
      } else if (def.type === 'select' && !def.options.some((o) => String(o.value) === String(v))) {
        return res.status(400).json({ error: 'invalid value for ' + def.label });
      }
    }
  }
  res.json(collections.setState(req.params.slug, { hidden, animate, speed, choice, controls }));
});

// Resolve a Token ID to its title + preview WITHOUT adding (drives the add-flow preview).
app.post('/api/collections/:slug/preview', ah(async (req, res) => {
  if (!collections.bySlug(req.params.slug)) return res.status(404).json({ error: 'unknown collection' });
  try {
    const info = await collections.resolveToken(req.params.slug, (req.body || {}).tokenId);
    // Return the preview as a data URL so it renders under the control panel's strict CSP.
    res.json({ tokenId: info.tokenId, title: info.title, image: await collections.toDataUrl(info.image) });
  } catch (e) { res.status(400).json({ error: e.message }); }
}));

// Add a piece: re-resolve on the server (authoritative), store the OFFICIAL url verbatim, mirror
// the shared bundle once, cache the thumbnail, then it's a normal Library row.
app.post('/api/collections/:slug/add', ah(async (req, res) => {
  const c = collections.bySlug(req.params.slug);
  if (!c) return res.status(404).json({ error: 'unknown collection' });
  let info;
  try { info = await collections.resolveToken(c.slug, (req.body || {}).tokenId); }
  catch (e) { return res.status(400).json({ error: e.message }); }
  const filename = `oo-connected-${c.slug}-${info.tokenId}`;
  if (db.getLibraryItemByFilename(filename)) return res.status(409).json({ error: 'That piece is already in your library.' });
  try { await collections.mirrorBundle(c.slug, info.sourceUrl, info.tokenId); }
  catch (e) { return res.status(502).json({ error: 'Could not download the artwork: ' + e.message }); }
  const thumb = await collections.cacheThumb(c.slug, info.tokenId, info.image);
  res.json(db.addConnectedItem({ filename, title: info.title, source_url: info.sourceUrl, collection: c.slug, token_id: info.tokenId, thumb }));
}));

// ── Rotation curation (HANDOFF §7) — membership rides on the library row; order is its own call ──
// ── Folder Collections (HANDOFF §17, Phase A) ───────────────────────
// The active Folder Collection id if a folder is the Display Source and still exists, else null
// (falling back to the Library). One place for the "is a folder live?" check.
function folderSourceId() {
  const src = db.getSetting('display_source', 'library');
  if (!src || src === 'library') return null;
  const f = db.getFolderCollection(Number(src));
  return f ? f.id : null;
}

// A friendly, home-relative path for display (e.g. ~/Videos/Sample Clips).
const HOME_DIR = os.homedir();
const displayPath = (p) => (p === HOME_DIR ? '~' : p.startsWith(HOME_DIR + path.sep) ? '~' + p.slice(HOME_DIR.length) : p);

// Folder Collections shared to LAN Displays (§17 Phase B). Open and PATH-FREE, unlike /api/folders
// below (which is gated and returns displayPath): a frame reads this with no credential to list the
// folders this host is serving and show them in its own Rotation Source dropdown. Media bytes come
// from the existing public /folder-media; per-folder item manifests from /:id/items.
app.get('/api/shared-folders', (_req, res) => {
  const me = identity.identity();
  res.json({
    host: { id: me.id, name: me.name }, // so a client can confirm which host answered at this address
    folders: db.listFolderCollections().map((f) => {
      const reachable = folders.reachable(f.path);
      return {
        id: f.id, name: f.name, artist: f.artist, fit: f.fit, order: f.order,
        count: reachable ? folders.count(f.path) : 0, reachable,
        // deliberately NO path: this endpoint is credential-free and must never leak the filesystem.
      };
    }),
  });
});

// The item manifest for one shared folder (§17 Phase B), path-free: the same display-item shape the
// local rotation already uses (id / filename / format / kind / fit / src), so a frame builds its
// rotation and its cache keys from it directly. `src` is host-relative (/folder-media/<id>/<file>);
// the frame prepends this host's base URL to fetch the bytes, then serves its own cache copy.
app.get('/api/shared-folders/:id/items', (req, res) => {
  const folder = db.getFolderCollection(Number(req.params.id));
  if (!folder) return res.status(404).json({ error: 'no such folder' });
  res.json({
    id: folder.id, name: folder.name, artist: folder.artist, fit: folder.fit, order: folder.order,
    items: folders.itemsFor(folder),
  });
});

// List folders for the Rotation Source dropdown. On a standalone Host these are the LOCAL saved
// folders (managed here). On the FRAME they are the folders SERVED BY a Mac over the LAN (§17 Phase
// B): the same response shape so the dropdown renders unchanged, but sourced from remote-folders and
// carrying no local-only fields (path/displayPath). Management (add/edit) is a Mac-side action, so
// the frame's control panel hides that card; `remote:true` lets it show the "no Mac found" hint.
app.get('/api/folders', ah(async (_req, res) => {
  const source = db.getSetting('display_source', 'library');
  if (identity.deviceRole() === 'frame') {
    const list = await remote.list();
    return res.json({
      source, remote: true,
      folders: list.map((f) => ({
        id: f.ref, name: f.name, artist: f.artist, fit: f.fit, order: f.order,
        count: f.count, reachable: f.reachable, active: f.ref === source, host: f.hostName,
      })),
    });
  }
  const activeId = folderSourceId();
  res.json({
    source,
    root: folders.FOLDER_ROOT,
    folders: db.listFolderCollections().map((f) => {
      const reachable = folders.reachable(f.path);
      return { ...f, reachable, count: reachable ? folders.count(f.path) : 0, active: f.id === activeId, displayPath: displayPath(f.path) };
    }),
  });
}));

// Browse the host's folders (sandboxed to folders.FOLDER_ROOT) so the owner can pick one without typing.
app.get('/api/folders/browse', (req, res) => {
  const view = folders.browse(req.query.path);
  if (!view) return res.status(400).json({ error: 'that folder is outside the allowed area or unreadable' });
  res.json(view);
});

// Register a folder (staging — it does not change the display until selected as the source, §17).
app.post('/api/folders', (req, res) => {
  const { path: p, name, artist, fit, order } = req.body || {};
  const v = folders.validateFolderPath(p);
  if (v.error) return res.status(400).json({ error: v.error });
  if (fit !== undefined && !FITS.has(fit)) return res.status(400).json({ error: 'fit must be fit|fill' });
  if (order !== undefined && !MODES.has(order)) return res.status(400).json({ error: 'order must be sequence|shuffle' });
  if (db.getFolderCollectionByPath(v.path)) return res.status(409).json({ error: 'that folder is already added' });
  const cleanName = (typeof name === 'string' && name.trim()) ? name.trim().slice(0, 80) : path.basename(v.path);
  const cleanArtist = (typeof artist === 'string' && artist.trim()) ? artist.trim().slice(0, 80) : null;
  res.status(201).json(db.addFolderCollection({ path: v.path, name: cleanName, artist: cleanArtist, fit, order }));
});

// Edit a folder's Name / Artist / Fit / Order (all staging; the folder is configured here and nowhere
// else, §17). A blank name falls back to the folder's own basename.
app.patch('/api/folders/:id', (req, res) => {
  const folder = db.getFolderCollection(Number(req.params.id));
  if (!folder) return res.status(404).json({ error: 'not found' });
  const { name, artist, fit, order } = req.body || {};
  if (fit !== undefined && !FITS.has(fit)) return res.status(400).json({ error: 'fit must be fit|fill' });
  if (order !== undefined && !MODES.has(order)) return res.status(400).json({ error: 'order must be sequence|shuffle' });
  const fields = { artist, fit, order };
  if (name !== undefined) fields.name = (typeof name === 'string' && name.trim()) ? name.trim().slice(0, 80) : path.basename(folder.path);
  res.json(db.updateFolderCollection(folder.id, fields));
});

// Delete a folder definition. If it was the live source, fall back to the Library so the display never
// points at a folder that no longer exists.
app.delete('/api/folders/:id', (req, res) => {
  const folder = db.getFolderCollection(Number(req.params.id));
  if (!folder) return res.status(404).json({ error: 'not found' });
  db.deleteFolderCollection(folder.id);
  folders.forget(folder.path);
  if (String(db.getSetting('display_source', 'library')) === String(folder.id)) db.setSetting('display_source', 'library');
  res.json({ ok: true });
});

// True when the request comes from the machine running the player itself (loopback) — i.e. the
// browser is open ON the host. The native folder chooser opens on the host, so it's only usable then.
function isLocalRequest(req) {
  const ip = (req.ip || req.socket.remoteAddress || '').replace(/^::ffff:/, '');
  return ip === '127.0.0.1' || ip === '::1';
}

// Pick a folder with the host's NATIVE file dialog (HANDOFF §17): on macOS the standard "choose
// folder" chooser via AppleScript, which opens on the machine running the player (where the folder
// lives) and can navigate the whole Mac. A human at the machine chooses, so this path is not limited
// to the browse sandbox. The chooser opens ON THE HOST, so a request from another device (a phone or
// another computer) returns `remote:true` instead of popping a dialog nobody is in front of; the
// control panel then shows a brief on-attempt note. Non-macOS returns `unsupported` (the in-browser
// browser fallback). A local request blocks until the user picks or cancels.
app.post('/api/folders/pick', ah(async (req, res) => {
  if (process.platform !== 'darwin') return res.json({ unsupported: true });
  if (!isLocalRequest(req)) return res.json({ remote: true });
  const script = 'POSIX path of (choose folder with prompt "Choose a folder for OpenObject to display")';
  let picked;
  try {
    picked = await new Promise((resolve, reject) => {
      execFile('osascript', ['-e', script], { timeout: 180000 }, (err, stdout, stderr) => {
        if (err) { err.stderr = stderr; return reject(err); }
        resolve(String(stdout).trim());
      });
    });
  } catch (e) {
    if (/User canceled/i.test((e && (e.stderr || e.message)) || '')) return res.json({ cancelled: true });
    return res.status(500).json({ error: 'Could not open the folder chooser.' });
  }
  if (!picked) return res.json({ cancelled: true });
  picked = picked.replace(/\/+$/, ''); // osascript returns a trailing slash
  let st;
  try { st = fs.statSync(picked); } catch { return res.status(400).json({ error: 'That folder could not be read.' }); }
  if (!st.isDirectory()) return res.status(400).json({ error: 'That is not a folder.' });
  const dup = db.getFolderCollectionByPath(picked);
  if (dup) return res.status(409).json({ error: 'that folder is already added', id: dup.id });
  res.status(201).json(db.addFolderCollection({ path: picked, name: path.basename(picked), artist: null, fit: 'fit', order: 'sequence' }));
}));

// Reveal a folder in the host's file manager (Finder on macOS), so the owner can see what's in it.
// Best-effort and non-blocking; opens on the machine running the player (where the folder lives).
app.post('/api/folders/:id/open', (req, res) => {
  const folder = db.getFolderCollection(Number(req.params.id));
  if (!folder) return res.status(404).json({ error: 'not found' });
  const opener = process.platform === 'darwin' ? 'open' : process.platform === 'linux' ? 'xdg-open' : null;
  if (!opener) return res.status(400).json({ error: 'not supported here' });
  execFile(opener, [folder.path], () => {}); // fire and forget
  res.json({ ok: true });
});

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

// ── Rotation settings (global, equal-time) + Pin + Sleep Schedule ──────
const toMinutes = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
const sanitizeDays = (days) =>
  Array.isArray(days)
    ? [...new Set(days.map(Number))].filter((d) => Number.isInteger(d) && d >= 0 && d <= 6).sort((a, b) => a - b)
    : [];
// One window vs the clock + the day it falls on. An overnight window (end <= start) belongs to the
// day it begins: its evening half counts as today, its after-midnight half as the day before.
function windowAsleep(r, dow, nowMin) {
  if (!r.days.length) return false;              // no days selected = inactive
  const s = toMinutes(r.start), e = toMinutes(r.end);
  if (s === e) return false;                     // zero-length window = off
  if (s < e) return r.days.includes(dow) && nowMin >= s && nowMin < e;  // same-day window
  if (nowMin >= s) return r.days.includes(dow);                         // overnight, before midnight
  return nowMin < e && r.days.includes((dow + 6) % 7);                  // overnight, after midnight
}
// Just the schedule: is a sleep window active right now (ignoring the manual overrides)?
function scheduledAsleep(settings, now = new Date()) {
  const dow = now.getDay(), nowMin = now.getHours() * 60 + now.getMinutes();
  return settings.sleepRanges.some((r) => windowAsleep(r, dow, nowMin));
}
// The one signal the display flips on (HANDOFF §13). Two manual overrides sit on top of the schedule:
// manual Sleep (manualBlank) forces asleep until woken; manual Wake (wakeUntil) holds the schedule off
// until the next window begins, so "Wake" during a sleep window keeps the art on, then the schedule resumes.
function isAsleep(settings, now = new Date()) {
  if (settings.manualBlank) return true;                                 // manual Sleep: off until woken
  if (settings.wakeUntil && now.getTime() < settings.wakeUntil) return false; // manual Wake: schedule suppressed until the next window
  return scheduledAsleep(settings, now);
}
// The next moment a sleep window begins (ms epoch), scanning the week ahead, or 0 if none. Set as the
// wake-until point when the owner Wakes mid-window, so the schedule takes back over at the next sleep.
function nextSleepStart(settings, now = new Date()) {
  let best = Infinity;
  for (const r of settings.sleepRanges) {
    if (!r.days.length || toMinutes(r.start) === toMinutes(r.end)) continue; // inactive / zero-length never sleeps
    const startMin = toMinutes(r.start);
    for (let ahead = 0; ahead <= 7; ahead++) {
      const d = new Date(now);
      d.setDate(d.getDate() + ahead);
      d.setHours(Math.floor(startMin / 60), startMin % 60, 0, 0);
      if (d.getTime() > now.getTime() && r.days.includes(d.getDay())) { best = Math.min(best, d.getTime()); break; }
    }
  }
  return best === Infinity ? 0 : best;
}
// Read + normalize. New windows carry days[]; older {enabled,...} windows migrate (enabled = all
// seven days, so behavior is unchanged), and anything malformed is dropped. Capped at three.
function readSleepRanges() {
  let v;
  try { v = JSON.parse(db.getSetting('sleep_ranges', '')); } catch { return []; }
  if (!Array.isArray(v)) return [];
  return v
    .filter((r) => r && typeof r.start === 'string' && typeof r.end === 'string')
    .map((r) => ({
      start: String(r.start),
      end: String(r.end),
      days: Array.isArray(r.days) ? sanitizeDays(r.days) : (r.enabled ? SLEEP_DAYS_ALL.slice() : []),
    }))
    .slice(0, 3);
}

function currentSettings() {
  const pin = db.getSetting('pinned_id', '');
  const s = {
    durationMs: Number(db.getSetting('duration_ms', DEFAULT_DURATION_MS)) || DEFAULT_DURATION_MS,
    mode: db.getSetting('rotation_mode', DEFAULT_MODE),
    pinnedId: pin ? Number(pin) : null, // one piece held permanently (HANDOFF §7), or null
    sleepRanges: readSleepRanges(),     // up to three day-aware sleep windows (HANDOFF §13)
    manualBlank: db.getSetting('manual_blank', '') === '1', // manual Sleep: off until woken
    wakeUntil: Number(db.getSetting('wake_until', '')) || 0, // manual Wake: schedule held off until this ms (0 = none)
    librarySort: db.getSetting('library_sort', db.DEFAULT_LIBRARY_SORT), // Library grid order (HANDOFF §7)
    libraryFilter: db.getSetting('library_filter', 'all'), // Library view filter: all | rotation (HANDOFF §7)
    retroArcade,                        // runtime-only easter-egg flag (never persisted; see /api/arcade)
    hostName: identity.hostName(),          // this Host's effective friendly name (custom, or the default)
    hostNameCustom: db.getSetting('host_name', ''), // the raw override ('' = using the default); what the Name field edits
    hostNameDefault: identity.defaultHostName(),     // the per-machine fallback, shown as the field's placeholder
    displaySource: db.getSetting('display_source', 'library'), // 'library' or a folder id (HANDOFF §17)
  };
  s.asleep = isAsleep(s); // the live state, so the control panel can label the button Sleep/Wake by what's true now
  return s;
}

app.get('/api/settings', (_req, res) => res.json(currentSettings()));

app.put('/api/settings', (req, res) => {
  const { durationMs, mode, sleepRanges, manualBlank, librarySort, libraryFilter, hostName, displaySource } = req.body || {};
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
      sleepRanges.length <= 3 &&
      sleepRanges.every((r) =>
        r && HHMM.test(r.start) && HHMM.test(r.end) &&
        Array.isArray(r.days) && r.days.every((d) => Number.isInteger(d) && d >= 0 && d <= 6));
    if (!ok) return res.status(400).json({ error: 'sleepRanges must be up to three {start:"HH:MM", end:"HH:MM", days:[0-6]}' });
    db.setSetting('sleep_ranges', JSON.stringify(sleepRanges.map((r) => ({ start: r.start, end: r.end, days: sanitizeDays(r.days) }))));
    db.setSetting('wake_until', ''); // editing the schedule cancels any active manual Wake, so the new windows take effect at once
  }
  if (manualBlank !== undefined) {
    if (typeof manualBlank !== 'boolean') return res.status(400).json({ error: 'manualBlank must be a boolean' });
    // manualBlank is the Sleep/Wake toggle: true = Sleep now (off until woken); false = Wake now.
    if (manualBlank) {
      db.setSetting('manual_blank', '1');
      db.setSetting('wake_until', '');
    } else {
      db.setSetting('manual_blank', '');
      // If a sleep window is live right now, hold the schedule off until the next window begins; otherwise just wake.
      const now = new Date(), s = currentSettings();
      db.setSetting('wake_until', scheduledAsleep(s, now) ? String(nextSleepStart(s, now)) : '');
    }
  }
  if (librarySort !== undefined) {
    if (!LIBRARY_SORTS.has(librarySort)) return res.status(400).json({ error: 'librarySort must be recent|oldest|title|artist' });
    db.setSetting('library_sort', librarySort);
  }
  if (libraryFilter !== undefined) {
    if (!LIBRARY_FILTERS.has(libraryFilter)) return res.status(400).json({ error: 'libraryFilter must be all|rotation' });
    db.setSetting('library_filter', libraryFilter);
  }
  if (hostName !== undefined) {
    if (typeof hostName !== 'string') return res.status(400).json({ error: 'hostName must be a string' });
    // Trim and cap; an empty value clears the override so hostName() falls back to the per-machine default.
    const trimmed = hostName.trim().slice(0, 40);
    const before = db.getSetting('host_name', '');
    db.setSetting('host_name', trimmed);
    // Re-advertise over Bonjour so discovery clients (the Mac app picker) see the new name without a
    // restart. Best-effort and off the playback path: readvertise never throws.
    if (trimmed !== before) readvertise();
  }
  if (displaySource !== undefined) {
    // The either/or switch (HANDOFF §17): 'library' (default) or a saved folder id. Selecting a folder
    // makes it the live source at once; the Library rotation is preserved untouched underneath.
    const src = String(displaySource);
    const okLocal = src === 'library' || !!db.getFolderCollection(Number(src));
    // On the frame the source may be a REMOTE folder ref (remote:<hostId>:<folderId>, §17 Phase B);
    // accept a well-formed ref (the dropdown only ever offers real ones). Its live reachability is
    // handled at display time, not here.
    const okRemote = identity.deviceRole() === 'frame' && !!remoteFolders.parseRef(src);
    if (!okLocal && !okRemote) {
      return res.status(400).json({ error: 'displaySource must be "library" or a folder id' });
    }
    db.setSetting('display_source', src);
    // Leaving a remote folder (to Library, a local folder, or nothing): wipe the frame's cache so no
    // folder files linger at rest (§17). A switch to ANOTHER remote folder is wiped by setActive on the
    // next /api/display poll; here we only cover leaving remote-folder mode.
    if (identity.deviceRole() === 'frame' && !remoteFolders.parseRef(src)) folderCache.clear();
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

// Retro Arcade on/off (the hidden easter egg). Runtime-only (see the `retroArcade` flag above): never
// stored, so the frame always wakes to art. Gated like every other control when a password is set; the
// kiosk reads the flag via /api/display, which stays open. PUT turns the demo on, DELETE turns it off.
app.put('/api/arcade', (_req, res) => { retroArcade = true; res.json({ retroArcade }); });
app.delete('/api/arcade', (_req, res) => { retroArcade = false; res.json({ retroArcade }); });

// What the display plays: while asleep (a sleep window or manual Blank, §13) it serves
// `asleep:true` and the display shows the dimmed mark. Otherwise a pinned piece overrides
// everything — held permanently even if not in the Rotation (§7) — else the Rotation in order.
// Connected pieces carry their collection's current animate-on-load setting so the display knows
// whether to fire the bundle's animate hook, plus how to build the iframe src: `perToken` (per-token
// bundle path vs the shared one) and `rpcUrl` (a liveRpc collection's swappable public node, which
// the display appends as the piece's ?rpc_url override so it animates from live on-chain state).
const withConnectedFlags = (item) => {
  if (item.kind !== 'connected') return item;
  const c = collections.bySlug(item.collection);
  const st = collections.getState(item.collection);
  return {
    ...item,
    // A speedControl collection is driven by `speed` (the cosine sweep), not the on/off animate hook.
    animate: st && !(c && c.speedControl) ? st.animate : false,
    speed: c && c.speedControl ? (st ? st.speed : c.speedDefault) : null, // 0..10 motion (0 = static)
    choice: c && c.choice ? (st ? st.choice : c.choice.default) : null, // selected option value → ?oochoice
    controls: c && Array.isArray(c.controls) && c.controls.length && st ? st.controls : null, // general controls → ?oo_<key>
    perToken: !!(c && c.perToken),
    rpcUrl: c && c.liveRpc ? c.rpc : null,
    crop: c && c.crop ? c.crop : null, // art occupies this centered fraction; display zooms it edge to edge
    aspect: c && c.aspect ? c.aspect : null, // declared aspect → display letterboxes it natively (§6)
  };
};

app.get('/api/display', ah(async (_req, res) => {
  const settings = currentSettings();

  // Frame: a REMOTE Mac folder as the source (§17 Phase B). Fetch its manifest from the Mac and rewrite
  // each item's media URL to the frame's OWN cache route (/folder-media/<folderKey>/<file>), so the
  // display plays only from the frame's cache, never the network (§9). Mark the cache active (it wipes
  // on a change of folder). If the Mac is unreachable with nothing cached yet, fall through to the
  // Library so the screen is never blank (§17 error state 2).
  const remoteRef = identity.deviceRole() === 'frame' ? remoteFolders.parseRef(settings.displaySource) : null;
  if (remoteRef) {
    const man = await remote.items(settings.displaySource);
    if (man && man.items.length) {
      const key = remoteFolders.folderKey(remoteRef.hostId, remoteRef.folderId);
      folderCache.setActive(key);
      const fit = man.folder.fit === 'fill' ? 'fill' : 'fit';
      return res.json({
        items: man.items.map((it) => ({
          id: it.id, filename: it.filename, format: it.format, kind: it.kind, fit,
          src: `/folder-media/${key}/${encodeURIComponent(it.filename)}`,
        })),
        durationMs: settings.durationMs,
        mode: MODES.has(man.folder.order) ? man.folder.order : DEFAULT_MODE,
        pinnedId: null,
        asleep: settings.asleep,
        retroArcade: settings.retroArcade,
        source: 'folder',
      });
    }
  }

  // Local Folder Collection as the Display Source (HANDOFF §17): play that folder's compliant files in
  // place, timed by the global duration, ordered by the folder's own Sequence/Shuffle (the Library's
  // rotation and order stay untouched underneath). Pin does not apply in folder mode.
  const activeId = folderSourceId();
  if (activeId != null) {
    const folder = db.getFolderCollection(activeId);
    return res.json({
      items: folders.itemsFor(folder),
      durationMs: settings.durationMs,
      mode: MODES.has(folder.order) ? folder.order : DEFAULT_MODE,
      pinnedId: null,
      asleep: settings.asleep,
      retroArcade: settings.retroArcade,
      source: 'folder',
    });
  }
  const pinned = settings.pinnedId != null ? db.getLibraryItem(settings.pinnedId) : null;
  res.json({
    items: (pinned ? [pinned] : db.listRotation()).map(withConnectedFlags),
    durationMs: settings.durationMs,
    mode: settings.mode,
    pinnedId: settings.pinnedId,
    asleep: settings.asleep,
    retroArcade: settings.retroArcade, // hidden self-playing demo: the display swaps to the canvas
    source: 'library',
  });
}));

// ── Self-update from GitHub (HANDOFF §15) ───────────────────────────
// Owner-initiated, never automatic, never in the playback path. All git logic lives in
// src/updater.js; these routes are the thin control-panel surface.

// Instant status for page load — no network, so it's offline-safe and never blocks.
app.get('/api/update', ah(async (_req, res) => {
  res.json({ ...(await updater.localStatus()), supervised: SUPERVISED });
}));

// Check for updates: fetch + compare to the upstream (origin/main). A network failure → offline.
app.post('/api/update/check', ah(async (_req, res) => {
  res.json(await updater.check());
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
    supervised: SUPERVISED, // this Host can soft-restart itself (relaunch available) → show Restart
    isDevice: process.platform === 'linux', // this Host can OS-power (the frame) → show Reboot / Shut down
    role: identity.deviceRole(), // 'frame' (the XXL appliance) or 'standalone'; drives the Folder Collections UI fork (§17 Phase B)
    port: PORT,
    // openobject.local resolves only where mDNS is configured (the installed frame, which is Linux),
    // not on a Mac/standalone, so only advertise it there; the control panel hides the line otherwise.
    mdns: process.platform === 'linux' ? 'openobject.local' : null,
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

// Who is this Host? (HANDOFF §20; MAC-APP-PLAN §A3.) The discovery surface: a Display or Control
// client browsing the network reads this to name a Host and tell it apart from others. Same fields
// as the Bonjour TXT records. Open (see AUTH_OPEN) so a Host is discoverable-by-name behind a
// password. `role` is 'host' because this server is always the Host (server.js header).
app.get('/api/identity', (_req, res) => {
  const me = identity.identity();
  res.json({ id: me.id, name: me.name, role: 'host', version: require('./package.json').version, port: PORT });
});

// Liveness probe — also how the Phase-1 self-update flow confirms the player came back up
// after restarting itself: `commit` is this checkout's HEAD, so the control panel can tell a
// new version is live (HANDOFF §15). Carries the Host id/name too so one probe both confirms
// liveness and says who answered.
app.get('/healthz', (_req, res) => {
  const me = identity.identity();
  res.json({ ok: true, app: 'openobject', id: me.id, name: me.name, version: require('./package.json').version, commit: updater.cachedCommitSync(), boot: BOOT_ID });
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

// The live Bonjour advertisement handle, kept at module scope so a host rename (PUT /api/settings
// hostName) can re-advertise with the new name without a restart. readvertise() stops any current
// advertisement and publishes a fresh one from the current identity; best-effort, never throws.
let advertisement = null;
function readvertise() {
  try { advertisement && advertisement.stop(); } catch { /* ignore */ }
  const me = identity.identity();
  advertisement = discovery.advertise({ name: me.name, port: PORT, id: me.id, version: require('./package.json').version });
}

// Cache the running commit for /healthz (HANDOFF §15) before serving; never block boot on it.
updater.refreshCommitCache().finally(() => {
  app.listen(PORT, HOST, () => {
    console.log(`OpenObject player listening on http://localhost:${PORT}`);
    console.log(`  • control  →  http://localhost:${PORT}/`);
    console.log(`  • display  →  http://localhost:${PORT}/display`);
    console.log(`  • version  →  ${require('./package.json').version} (commit ${updater.cachedCommitSync() || '—'})${SUPERVISED ? ' · supervised' : ''}`);

    // Advertise this Host over Bonjour/mDNS so Displays/Controls can find it (MAC-APP-PLAN §A2).
    // Best-effort and off the playback path: discovery.advertise never throws, so a failure here
    // leaves the player serving exactly as before, just not auto-discoverable.
    readvertise();

    // On the frame (OO_ROLE=frame), also BROWSE for other Hosts so a Folder Collection served by a
    // Mac can be discovered and selected (HANDOFF §17 Phase B). Only the frame consumes: a standalone
    // Mac Host is the server and does its browsing in the Mac app, not here. Best-effort and off the
    // playback path, exactly like advertising.
    if (identity.deviceRole() === 'frame') {
      discoveryBrowser = discovery.browse({ selfId: identity.identity().id });
    }

    // Withdraw the advertisement on a clean stop (Ctrl-C, or systemd's SIGTERM on the frame) so
    // clients don't briefly see a dead Host. The supervisor short-circuits on `stopping`, so the
    // exit code here is irrelevant; a self-update restart (process.exit(RESTART_CODE)) simply
    // re-advertises on relaunch. This does not change the frame's stop/restart behavior.
    for (const sig of ['SIGINT', 'SIGTERM']) {
      process.once(sig, () => {
        try { advertisement && advertisement.stop(); } catch { /* ignore */ }
        try { discoveryBrowser && discoveryBrowser.stop(); } catch { /* ignore */ }
        process.exit(0);
      });
    }
  });
});

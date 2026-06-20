'use strict';

// Local SQLite store for the library, rotation, and settings.
//
// Uses Node's built-in `node:sqlite` (Node >= 22.5) — zero native dependencies and no
// build step, which fits the revivability goal: a future owner only needs Node. All DB
// access is contained in this one file, so swapping to better-sqlite3 later (should the
// experimental API ever churn) stays a localized change.
//
// The database and uploads are runtime data — gitignored, never committed (HANDOFF §8, §15).

const path = require('path');
const fs = require('fs');

// node:sqlite is stable underneath (it IS SQLite), but Node still tags the *JS API*
// "experimental" and prints one startup warning. The frame owner never sees server logs;
// we silence ONLY that one line so the builder's boot log stays clean — every other Node
// warning (deprecations, etc.) still prints. Must run before node:sqlite is loaded.
const _emitWarning = process.emitWarning.bind(process);
process.emitWarning = (warning, ...rest) => {
  const opt = rest[0];
  const type = typeof opt === 'string' ? opt : opt && opt.type;
  const msg = typeof warning === 'string' ? warning : warning && warning.message;
  if (type === 'ExperimentalWarning' && msg && msg.includes('SQLite')) return;
  return _emitWarning(warning, ...rest);
};
const { DatabaseSync } = require('node:sqlite');

const DATA_DIR = process.env.OO_DATA_DIR || path.join(__dirname, '..', 'data');
const UPLOADS_DIR = process.env.OO_UPLOADS_DIR || path.join(__dirname, '..', 'uploads');
const DB_PATH = path.join(DATA_DIR, 'openobject.sqlite');

let db = null;

function initDb() {
  if (db) return db;
  fs.mkdirSync(DATA_DIR, { recursive: true });
  fs.mkdirSync(UPLOADS_DIR, { recursive: true });
  db = new DatabaseSync(DB_PATH);
  db.exec('PRAGMA journal_mode = WAL;');

  // Global settings (duration, rotation order, …) as simple key/value rows.
  db.exec(`
    CREATE TABLE IF NOT EXISTS settings (
      key   TEXT PRIMARY KEY,
      value TEXT
    );
  `);

  // Library = every uploaded clip (HANDOFF §7). Fit/Fill is per-clip (§6). Duration is
  // global/equal-time (a single setting), so there is intentionally no per-clip duration.
  db.exec(`
    CREATE TABLE IF NOT EXISTS library (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      filename      TEXT NOT NULL UNIQUE,        -- stored file on disk (UPLOADS_DIR)
      original_name TEXT NOT NULL,               -- name as uploaded, for display
      mime          TEXT,
      format        TEXT NOT NULL,               -- jpeg|png|gif|avif|webp|svg|mp4|mov|webm
      kind          TEXT NOT NULL,               -- still|animated|video (drives behavior)
      bytes         INTEGER NOT NULL,
      width         INTEGER,
      height        INTEGER,
      fit           TEXT NOT NULL DEFAULT 'fit', -- per-clip Fit/Fill (HANDOFF §6)
      in_rotation   INTEGER NOT NULL DEFAULT 1,  -- 1 = currently in the Rotation (HANDOFF §7)
      position      INTEGER,                     -- curated Rotation order; lower plays earlier
      created_at    TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  // Curation columns (in_rotation, position) were added after the first uploads shipped.
  // Add them in place for libraries created by the earlier schema, then seed a stable
  // order from upload order (id) so the existing rotation is unchanged. Idempotent.
  const cols = new Set(db.prepare('PRAGMA table_info(library)').all().map((c) => c.name));
  if (!cols.has('in_rotation')) db.exec('ALTER TABLE library ADD COLUMN in_rotation INTEGER NOT NULL DEFAULT 1');
  if (!cols.has('position')) {
    db.exec('ALTER TABLE library ADD COLUMN position INTEGER');
    db.exec('UPDATE library SET position = id WHERE position IS NULL');
  }

  // Connected artwork (src/collections.js): a Library row whose source is a
  // hosted/on-chain URL rather than an uploaded file. kind='connected'; the official artwork URL
  // is stored verbatim in source_url, with a derived title (original_name) and cached thumbnail so
  // the card looks like any other piece. Columns added in place so older libraries upgrade cleanly.
  for (const col of ['source_url', 'collection', 'token_id', 'thumb']) {
    if (!cols.has(col)) db.exec(`ALTER TABLE library ADD COLUMN ${col} TEXT`);
  }

  // Per-frame curation of the supported collections list (the registry itself lives in code):
  // hidden = don't show when adding; animate = override the collection's animate-on-load default;
  // speed = a speedControl collection's 0..10 motion speed (NULL = use the registry default);
  // choice = a `choice` collection's selected option value (NULL = use the registry default).
  db.exec(`
    CREATE TABLE IF NOT EXISTS collection_state (
      slug    TEXT PRIMARY KEY,
      hidden  INTEGER NOT NULL DEFAULT 0,
      animate INTEGER,                      -- NULL = use the registry default
      speed   REAL,                         -- NULL = use the registry default (speedControl only)
      choice  TEXT                          -- NULL = use the registry default (choice control only)
    );
  `);
  // `speed`, then `choice`, were added after the first connected collections shipped — add them in
  // place for older libraries. Idempotent.
  const ccols = new Set(db.prepare('PRAGMA table_info(collection_state)').all().map((c) => c.name));
  if (!ccols.has('speed')) db.exec('ALTER TABLE collection_state ADD COLUMN speed REAL');
  if (!ccols.has('choice')) db.exec('ALTER TABLE collection_state ADD COLUMN choice TEXT');

  console.log(`SQLite ready (node:sqlite) → ${DB_PATH}`);
  return db;
}

function getDb() {
  return db || initDb();
}

// ── Settings (key/value) ────────────────────────────────────────────
function getSetting(key, fallback) {
  const row = getDb().prepare('SELECT value FROM settings WHERE key = ?').get(key);
  return row ? row.value : fallback;
}

function setSetting(key, value) {
  getDb()
    .prepare('INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value')
    .run(key, String(value));
}

// ── Library queries ─────────────────────────────────────────────────
function addLibraryItem(item) {
  const info = getDb()
    .prepare(
      `INSERT INTO library (filename, original_name, mime, format, kind, bytes, width, height, in_rotation, position)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, (SELECT COALESCE(MAX(position), -1) + 1 FROM library WHERE in_rotation = 1))`
    )
    .run(
      item.filename,
      item.original_name,
      item.mime ?? null,
      item.format,
      item.kind,
      item.bytes,
      item.width ?? null,
      item.height ?? null
    );
  return getLibraryItem(Number(info.lastInsertRowid));
}

// Connected artwork: a Library row sourced from a hosted/on-chain URL (no uploaded file).
// filename is a synthetic unique key (so the same piece can't be added twice); bytes is 0.
function addConnectedItem(item) {
  const info = getDb()
    .prepare(
      `INSERT INTO library (filename, original_name, mime, format, kind, bytes, in_rotation, position, source_url, collection, token_id, thumb)
       VALUES (?, ?, 'text/html', 'connected', 'connected', 0, 1, (SELECT COALESCE(MAX(position), -1) + 1 FROM library WHERE in_rotation = 1), ?, ?, ?, ?)`
    )
    .run(item.filename, item.title, item.source_url, item.collection, item.token_id, item.thumb ?? null);
  return getLibraryItem(Number(info.lastInsertRowid));
}

function getLibraryItemByFilename(filename) {
  return getDb().prepare('SELECT * FROM library WHERE filename = ?').get(filename) || null;
}

function countConnected(slug) {
  return getDb().prepare("SELECT COUNT(*) AS n FROM library WHERE kind = 'connected' AND collection = ?").get(slug).n;
}

// ── Connected-collection curation state (hidden / animate override / motion speed / choice) ──
function getCollectionState(slug) {
  return getDb().prepare('SELECT slug, hidden, animate, speed, choice FROM collection_state WHERE slug = ?').get(slug) || null;
}
function setCollectionState(slug, patch) {
  const cur = getCollectionState(slug) || { hidden: 0, animate: null, speed: null, choice: null };
  const hidden = patch.hidden !== undefined ? (patch.hidden ? 1 : 0) : cur.hidden;
  const animate = patch.animate !== undefined ? (patch.animate ? 1 : 0) : cur.animate;
  const speed = patch.speed !== undefined ? (patch.speed == null ? null : Number(patch.speed)) : cur.speed;
  const choice = patch.choice !== undefined ? (patch.choice == null ? null : String(patch.choice)) : cur.choice;
  getDb()
    .prepare(
      `INSERT INTO collection_state (slug, hidden, animate, speed, choice) VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(slug) DO UPDATE SET hidden = excluded.hidden, animate = excluded.animate, speed = excluded.speed, choice = excluded.choice`
    )
    .run(slug, hidden, animate, speed, choice);
}

// Library grid shows newest first; the Rotation is the curated subset in its chosen order.
function listLibrary() {
  return getDb().prepare('SELECT * FROM library ORDER BY id DESC').all();
}
function listRotation() {
  return getDb().prepare('SELECT * FROM library WHERE in_rotation = 1 ORDER BY position ASC, id ASC').all();
}

function getLibraryItem(id) {
  return getDb().prepare('SELECT * FROM library WHERE id = ?').get(id);
}

function setLibraryFit(id, fit) {
  if (!getLibraryItem(id)) return null;
  getDb().prepare('UPDATE library SET fit = ? WHERE id = ?').run(fit, id);
  return getLibraryItem(id);
}

// Add to / remove from the Rotation. Adding puts the piece at the end of the order
// (HANDOFF §7); removing leaves its old position dormant (ignored until re-added).
function setLibraryRotation(id, inRotation) {
  const row = getLibraryItem(id);
  if (!row) return null;
  const want = inRotation ? 1 : 0;
  if (row.in_rotation === want) return row; // already in the desired state — no reorder
  if (want === 1) {
    const { p } = getDb()
      .prepare('SELECT COALESCE(MAX(position), -1) + 1 AS p FROM library WHERE in_rotation = 1')
      .get();
    getDb().prepare('UPDATE library SET in_rotation = 1, position = ? WHERE id = ?').run(p, id);
  } else {
    getDb().prepare('UPDATE library SET in_rotation = 0 WHERE id = ?').run(id);
  }
  return getLibraryItem(id);
}

// Persist a new Rotation order. Renumbers the given members 0..n-1 in one transaction;
// ids that aren't current members are ignored (the WHERE guard).
function reorderRotation(ids) {
  const d = getDb();
  const upd = d.prepare('UPDATE library SET position = ? WHERE id = ? AND in_rotation = 1');
  d.exec('BEGIN');
  try {
    ids.forEach((id, i) => upd.run(i, Number(id)));
    d.exec('COMMIT');
  } catch (e) {
    d.exec('ROLLBACK');
    throw e;
  }
  return listRotation();
}

function deleteLibraryItem(id) {
  const row = getLibraryItem(id);
  if (!row) return null;
  getDb().prepare('DELETE FROM library WHERE id = ?').run(id);
  return row;
}

module.exports = {
  initDb,
  getDb,
  getSetting,
  setSetting,
  addLibraryItem,
  addConnectedItem,
  getLibraryItemByFilename,
  countConnected,
  getCollectionState,
  setCollectionState,
  listLibrary,
  listRotation,
  getLibraryItem,
  setLibraryFit,
  setLibraryRotation,
  reorderRotation,
  deleteLibraryItem,
  DATA_DIR,
  UPLOADS_DIR,
  DB_PATH,
};

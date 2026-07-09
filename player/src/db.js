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

// The install sample (the Bouncing OpenObject Logo, seeded into every fresh Library by the install step) is
// anchored to the BOTTOM of the Library grid by listLibrary, so it reads as the original piece that "came
// with the install" — beneath the owner's own pieces — regardless of when it was added (it may carry a high
// id if added by hand to an existing library, e.g. the bench frame). Sort-only: the card is otherwise
// identical to any other piece (no special row, badge, or handling). Pairs with the seed step.
const INSTALL_SAMPLE_COLLECTION = 'bouncing-openobject-logo';

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

  // Optional per-upload metadata (HANDOFF §7): a custom display title and artist the owner can set on an
  // uploaded piece (NULL = unset; the card then falls back to the filename / file size). Connected pieces
  // get their title/artist from the chain/registry, not here. Added in place so older libraries upgrade.
  for (const col of ['title', 'artist']) {
    if (!cols.has(col)) db.exec(`ALTER TABLE library ADD COLUMN ${col} TEXT`);
  }

  // Per-frame curation of the supported collections list (the registry itself lives in code):
  // hidden = don't show when adding; animate = override the collection's animate-on-load default;
  // speed = a speedControl collection's 0..10 motion speed (NULL = use the registry default);
  // choice = a `choice` collection's selected option value (NULL = use the registry default);
  // controls = a `controls` collection's general control values as JSON {key:value} (NULL = registry defaults).
  db.exec(`
    CREATE TABLE IF NOT EXISTS collection_state (
      slug     TEXT PRIMARY KEY,
      hidden   INTEGER NOT NULL DEFAULT 0,
      animate  INTEGER,                     -- NULL = use the registry default
      speed    REAL,                        -- NULL = use the registry default (speedControl only)
      choice   TEXT,                        -- NULL = use the registry default (choice control only)
      controls TEXT                         -- NULL = use registry defaults (general controls model; JSON {key:value})
    );
  `);
  // `speed`, then `choice`, then `controls`, were added after the first connected collections shipped — add
  // them in place for older libraries. Idempotent.
  const ccols = new Set(db.prepare('PRAGMA table_info(collection_state)').all().map((c) => c.name));
  if (!ccols.has('speed')) db.exec('ALTER TABLE collection_state ADD COLUMN speed REAL');
  if (!ccols.has('choice')) db.exec('ALTER TABLE collection_state ADD COLUMN choice TEXT');
  if (!ccols.has('controls')) db.exec('ALTER TABLE collection_state ADD COLUMN controls TEXT');

  // Folder Collections (HANDOFF §17): a saved local folder shown as an either/or Display Source, a
  // sibling of the Library (not Library rows). Phase A serves the folder in place; its files are never
  // copied into the Library. `play_order` is the per-folder Sequence/Shuffle override (SELECTs alias it
  // back to `order`, which is a SQL reserved word); `fit` applies to the whole folder. The active source
  // is the `display_source` setting ('library' or a folder id), so switching is a one-value flip.
  db.exec(`
    CREATE TABLE IF NOT EXISTS folder_collections (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      path       TEXT NOT NULL UNIQUE,
      name       TEXT NOT NULL,
      artist     TEXT,
      fit        TEXT NOT NULL DEFAULT 'fit',        -- fit|fill, whole-folder (HANDOFF §6, §17)
      play_order TEXT NOT NULL DEFAULT 'sequence',   -- sequence|shuffle, per-folder override (§7, §17)
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
  `);

  // The Library "Title" sort first shipped under the key "name" (its old label, 4a5bc26). Migrate a
  // persisted value so an existing setting keeps working after the rename; the API no longer accepts "name".
  if (getSetting('library_sort') === 'name') setSetting('library_sort', 'title');

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
// in_rotation defaults to 1 (a normal add lands in the Rotation); pass 0 to add it dormant
// (used by the first-run seed, so a fresh install boots to the idle screen, not the sample).
function addConnectedItem(item) {
  const inRotation = item.in_rotation === undefined ? 1 : item.in_rotation ? 1 : 0;
  const info = getDb()
    .prepare(
      `INSERT INTO library (filename, original_name, mime, format, kind, bytes, in_rotation, position, source_url, collection, token_id, thumb)
       VALUES (?, ?, 'text/html', 'connected', 'connected', 0, ?, (SELECT COALESCE(MAX(position), -1) + 1 FROM library WHERE in_rotation = 1), ?, ?, ?, ?)`
    )
    .run(item.filename, item.title, inRotation, item.source_url, item.collection, item.token_id, item.thumb ?? null);
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
  return getDb().prepare('SELECT slug, hidden, animate, speed, choice, controls FROM collection_state WHERE slug = ?').get(slug) || null;
}
function setCollectionState(slug, patch) {
  const cur = getCollectionState(slug) || { hidden: 0, animate: null, speed: null, choice: null, controls: null };
  const hidden = patch.hidden !== undefined ? (patch.hidden ? 1 : 0) : cur.hidden;
  const animate = patch.animate !== undefined ? (patch.animate ? 1 : 0) : cur.animate;
  const speed = patch.speed !== undefined ? (patch.speed == null ? null : Number(patch.speed)) : cur.speed;
  const choice = patch.choice !== undefined ? (patch.choice == null ? null : String(patch.choice)) : cur.choice;
  // controls arrives already serialised (a JSON string) from collections.setState, or null to clear.
  const controls = patch.controls !== undefined ? (patch.controls == null ? null : String(patch.controls)) : cur.controls;
  getDb()
    .prepare(
      `INSERT INTO collection_state (slug, hidden, animate, speed, choice, controls) VALUES (?, ?, ?, ?, ?, ?)
       ON CONFLICT(slug) DO UPDATE SET hidden = excluded.hidden, animate = excluded.animate, speed = excluded.speed, choice = excluded.choice, controls = excluded.controls`
    )
    .run(slug, hidden, animate, speed, choice, controls);
}

// Library grid sort options (HANDOFF §7). Every order keeps the install sample anchored to the BOTTOM
// of the grid: the `(collection = sample) ASC` primary key always sorts the sample row last, so it sits
// beneath the owner's own pieces however recently it was added, in every order. The ORDER BY fragments
// are a fixed allowlist (never interpolated from user input), so there is no SQL-injection surface.
// "title" sorts by the DISPLAYED title: a piece's custom title when set, else its filename/derived title
// (the same fallback the card shows). NULLIF('') treats a blank title as unset so COALESCE falls through.
// (This key first shipped as "name", its old UI label; initDb migrates a persisted "name" to "title".)
const LIBRARY_SORTS = {
  recent: 'id DESC',                                  // newest first (the default)
  oldest: 'id ASC',                                   // oldest first
  title: "COALESCE(NULLIF(title, ''), original_name) COLLATE NOCASE ASC, id DESC",  // A–Z, id tiebreaker
};
const DEFAULT_LIBRARY_SORT = 'recent';

// Sort-only; the Rotation is the curated subset in its own order (listRotation). An unknown/blank sort
// falls back to the default, so a stale value never breaks the grid.
function listLibrary(sort) {
  const order = LIBRARY_SORTS[sort] || LIBRARY_SORTS[DEFAULT_LIBRARY_SORT];
  return getDb()
    .prepare(`SELECT * FROM library ORDER BY (COALESCE(collection, '') = ?) ASC, ${order}`)
    .all(INSTALL_SAMPLE_COLLECTION);
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

// Set a piece's optional display title and/or artist (HANDOFF §7). A blank value clears the field to NULL,
// so the card falls back to the filename / file size. Only the fields present in `fields` are touched.
function setLibraryMeta(id, fields) {
  if (!getLibraryItem(id)) return null;
  const norm = (v) => { const s = String(v == null ? '' : v).trim(); return s === '' ? null : s; };
  if (fields.title !== undefined) getDb().prepare('UPDATE library SET title = ? WHERE id = ?').run(norm(fields.title), id);
  if (fields.artist !== undefined) getDb().prepare('UPDATE library SET artist = ? WHERE id = ?').run(norm(fields.artist), id);
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

// ── Folder Collections (HANDOFF §17) ────────────────────────────────
// Saved local folders shown as an either/or Display Source. Rows expose `order` (aliased from the
// `play_order` column, since `order` is a SQL reserved word); everything else maps straight through.
const FOLDER_COLS = 'id, path, name, artist, fit, play_order AS "order", created_at';

function listFolderCollections() {
  return getDb().prepare(`SELECT ${FOLDER_COLS} FROM folder_collections ORDER BY id ASC`).all();
}
function getFolderCollection(id) {
  return getDb().prepare(`SELECT ${FOLDER_COLS} FROM folder_collections WHERE id = ?`).get(Number(id)) || null;
}
function getFolderCollectionByPath(p) {
  return getDb().prepare(`SELECT ${FOLDER_COLS} FROM folder_collections WHERE path = ?`).get(String(p)) || null;
}
function addFolderCollection({ path: p, name, artist, fit, order }) {
  const info = getDb()
    .prepare('INSERT INTO folder_collections (path, name, artist, fit, play_order) VALUES (?, ?, ?, ?, ?)')
    .run(String(p), String(name), artist ?? null, fit === 'fill' ? 'fill' : 'fit', order === 'shuffle' ? 'shuffle' : 'sequence');
  return getFolderCollection(Number(info.lastInsertRowid));
}
// Patch only the fields present. A blank name is ignored (the column is NOT NULL; callers substitute
// the folder's basename before clearing), so the folder always keeps a display name.
function updateFolderCollection(id, fields) {
  if (!getFolderCollection(id)) return null;
  const d = getDb();
  const norm = (v) => { const s = String(v == null ? '' : v).trim(); return s === '' ? null : s; };
  if (fields.name !== undefined) { const n = norm(fields.name); if (n) d.prepare('UPDATE folder_collections SET name = ? WHERE id = ?').run(n, Number(id)); }
  if (fields.artist !== undefined) d.prepare('UPDATE folder_collections SET artist = ? WHERE id = ?').run(norm(fields.artist), Number(id));
  if (fields.fit !== undefined) d.prepare('UPDATE folder_collections SET fit = ? WHERE id = ?').run(fields.fit === 'fill' ? 'fill' : 'fit', Number(id));
  if (fields.order !== undefined) d.prepare('UPDATE folder_collections SET play_order = ? WHERE id = ?').run(fields.order === 'shuffle' ? 'shuffle' : 'sequence', Number(id));
  return getFolderCollection(id);
}
function deleteFolderCollection(id) {
  const row = getFolderCollection(id);
  if (!row) return null;
  getDb().prepare('DELETE FROM folder_collections WHERE id = ?').run(Number(id));
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
  LIBRARY_SORTS,
  DEFAULT_LIBRARY_SORT,
  listRotation,
  getLibraryItem,
  setLibraryFit,
  setLibraryMeta,
  setLibraryRotation,
  reorderRotation,
  deleteLibraryItem,
  listFolderCollections,
  getFolderCollection,
  getFolderCollectionByPath,
  addFolderCollection,
  updateFolderCollection,
  deleteFolderCollection,
  INSTALL_SAMPLE_COLLECTION,
  DATA_DIR,
  UPLOADS_DIR,
  DB_PATH,
};

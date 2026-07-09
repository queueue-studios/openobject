'use strict';

// Folder Collections — Phase A (local): show a chosen local folder as an either/or Display Source
// (HANDOFF §17). Nothing is copied into the Library; the folder's compliant files are scanned and
// shaped into the same display items the rotation already uses, and /folder-media streams them
// straight from disk. Freshness is live and always-on: an OS file-watch marks the scan cache dirty
// so added/removed files fold into the running rotation on the display's next poll (no include
// toggle). Phase B (the frame) will reuse this same item shape over a capped local cache; only the
// byte source changes, so nothing here is throwaway.

const path = require('path');
const fs = require('fs');
const os = require('os');
const { classify } = require('./formats');

// The folder browser and folder registration are sandboxed to this root, so a LAN client (even past
// the control-panel password) can't wander the whole filesystem. Defaults to the owner's home
// directory; override with OO_FOLDER_ROOT. Resolved once at load.
const FOLDER_ROOT = path.resolve(process.env.OO_FOLDER_ROOT || os.homedir());

// Is `p` inside (or equal to) the sandbox root? Guards both browsing and registration.
function withinRoot(p) {
  const r = path.resolve(p);
  return r === FOLDER_ROOT || r.startsWith(FOLDER_ROOT + path.sep);
}

// ── Scan (non-recursive): compliant files directly in the folder ────
// Top-level files only (no recursion); skips dotfiles and anything the formats allowlist rejects
// (HANDOFF §6), exactly like uploads. Sorted by name (case-insensitive) for a stable Sequence order.
// Returns [] and never throws if the folder is missing/unreadable (an unreachable folder reads as
// empty; see reachable()).
function scanRaw(folderPath) {
  let entries;
  try { entries = fs.readdirSync(folderPath, { withFileTypes: true }); }
  catch { return []; }
  const files = [];
  for (const ent of entries) {
    if (!ent.isFile()) continue;              // top-level files only
    if (ent.name.startsWith('.')) continue;   // OS noise (.DS_Store, etc.)
    const fmt = classify(ent.name);
    if (!fmt) continue;                        // unsupported → skip, no error (HANDOFF §6)
    files.push({ name: ent.name, format: fmt.format, kind: fmt.kind });
  }
  files.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  return files;
}

// A small per-folder cache invalidated by an OS file-watch, so a folder isn't re-read on every
// display poll (HANDOFF §17: near-zero idle cost, near-instant pickup). If a watch can't be set up
// (some network filesystems), we fall back to always re-scanning — correctness over efficiency.
const caches = new Map(); // folderPath -> { files, dirty, watcher, watchable }

function cacheFor(folderPath) {
  let c = caches.get(folderPath);
  if (c) return c;
  c = { files: [], dirty: true, watcher: null, watchable: true };
  try {
    c.watcher = fs.watch(folderPath, { persistent: false }, () => { c.dirty = true; });
    c.watcher.on('error', () => { c.watchable = false; }); // watch dropped → fall back to re-scan
  } catch { c.watchable = false; }
  caches.set(folderPath, c);
  return c;
}

function scan(folderPath) {
  const c = cacheFor(folderPath);
  if (c.dirty || !c.watchable) { c.files = scanRaw(folderPath); c.dirty = false; }
  return c.files;
}

// Stop and forget a folder's watcher/cache (on delete), so watchers don't leak.
function forget(folderPath) {
  const c = caches.get(folderPath);
  if (c && c.watcher) { try { c.watcher.close(); } catch {} }
  caches.delete(folderPath);
}

function reachable(folderPath) {
  try { return fs.statSync(folderPath).isDirectory(); } catch { return false; }
}

function count(folderPath) { return scan(folderPath).length; }

// ── Display items ───────────────────────────────────────────────────
// Shape a folder's compliant files into the item array the display already consumes (display.js):
// each carries a STABLE id (so a piece survives polls without restarting), the folder's Fit, and a
// `src` URL under /folder-media (the display uses item.src when present, else /uploads). Reshaped
// per call, so a Fit change on the folder takes effect without a re-scan.
function itemsFor(folderRow) {
  const fit = folderRow.fit === 'fill' ? 'fill' : 'fit';
  return scan(folderRow.path).map((f) => ({
    id: 'fc' + folderRow.id + ':' + f.name,   // stable synthetic id (folder + filename)
    filename: f.name,
    format: f.format,
    kind: f.kind,
    fit,
    src: '/folder-media/' + folderRow.id + '/' + encodeURIComponent(f.name),
  }));
}

// ── Folder browser (server-side) ────────────────────────────────────
// Lists the subfolders of `p` (default: the sandbox root) so the control panel can navigate to a
// folder to add, with no path typing. Sandboxed to FOLDER_ROOT. Also reports how many compliant
// media files sit directly in the current folder, so the owner can tell a good pick. Never lists
// files. Returns null (→ 400) for a path outside the sandbox or unreadable.
function browse(p) {
  const target = p ? path.resolve(String(p)) : FOLDER_ROOT;
  if (!withinRoot(target)) return null;
  let entries;
  try { entries = fs.readdirSync(target, { withFileTypes: true }); }
  catch { return null; }
  const dirs = entries
    .filter((e) => e.isDirectory() && !e.name.startsWith('.'))
    .map((e) => e.name)
    .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: 'base' }));
  const parent = path.dirname(target);
  return {
    path: target,
    parent: target === FOLDER_ROOT || !withinRoot(parent) ? null : parent,
    atRoot: target === FOLDER_ROOT,
    dirs,
    mediaCount: scanRaw(target).length,       // compliant files directly here (a good-pick hint)
  };
}

// Validate a path the owner is registering as a Folder Collection: it must sit inside the sandbox
// and be a readable directory. Returns { path } (resolved) or { error }.
function validateFolderPath(p) {
  if (typeof p !== 'string' || !p.trim()) return { error: 'a folder path is required' };
  const target = path.resolve(p);
  if (!withinRoot(target)) return { error: 'folder must be inside ' + FOLDER_ROOT };
  let st;
  try { st = fs.statSync(target); } catch { return { error: 'folder not found' }; }
  if (!st.isDirectory()) return { error: 'not a folder' };
  return { path: target };
}

// Resolve a /folder-media/<id>/<file> request to { root, name } for res.sendFile, or null. Rejects
// traversal (the file must be a single segment directly inside the folder) and non-compliant files;
// res.sendFile with root = the folder is the containment backstop.
function resolveMedia(folderRow, fileParam) {
  let name;
  try { name = path.basename(decodeURIComponent(String(fileParam))); } catch { return null; }
  if (!name || name.startsWith('.')) return null;
  if (!classify(name)) return null;           // only ever serve compliant files
  const abs = path.join(folderRow.path, name);
  if (path.dirname(abs) !== path.resolve(folderRow.path)) return null; // must be directly inside
  try { if (!fs.statSync(abs).isFile()) return null; } catch { return null; }
  return { root: path.resolve(folderRow.path), name };
}

module.exports = {
  FOLDER_ROOT,
  scan, count, reachable, forget,
  itemsFor,
  browse,
  validateFolderPath,
  resolveMedia,
};

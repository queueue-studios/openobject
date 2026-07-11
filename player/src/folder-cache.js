'use strict';

// Folder Collections — Phase B frame cache (HANDOFF §17). An EPHEMERAL, bounded on-disk buffer for
// the media of the ACTIVE remote Mac folder. The frame's display plays only from here, never straight
// off the network (§9): a file is fetched from the Mac on first need, written once, and replayed from
// disk. The buffer is WIPED on engine start (so a reboot returns fresh), on leaving folder mode or
// switching folders, and by a manual Clear. It is bounded by a hard byte CAP and a free-space FLOOR,
// so it can never crowd the Library or the OS; a folder larger than the cap streams the overflow
// through without caching, so playback never blocks on storage. No new deps (global fetch, node:fs).

const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const { Readable } = require('stream');
const { parseFolderKey } = require('./remote-folders');

const CAP_BYTES   = Number(process.env.OO_FOLDER_CACHE_CAP)   || 20 * 1024 * 1024 * 1024; // 20 GB
const FLOOR_BYTES = Number(process.env.OO_FOLDER_CACHE_FLOOR) || 15 * 1024 * 1024 * 1024; // keep this free

// A filesystem-safe cache filename: a hash of the original name, keeping the extension so the served
// content-type stays right. Avoids odd characters and cross-file collisions.
function safeName(file) {
  const ext = path.extname(String(file)).slice(0, 12);
  return crypto.createHash('sha1').update(String(file)).digest('hex').slice(0, 16) + ext;
}

// `resolveBase(hostId, folderId) -> Promise<baseUrl|null>`: the Mac's current LAN base URL, resolved
// live from discovery (so a changed IP is handled), or null when the Host is not currently reachable.
function create({ dir, resolveBase }) {
  let bytes = 0;        // cached bytes (tracked as we write; reset on a wipe)
  let activeKey = null; // the folderKey currently being served/cached

  const wipe = () => {
    try { fs.rmSync(dir, { recursive: true, force: true }); } catch { /* ignore */ }
    try { fs.mkdirSync(dir, { recursive: true }); } catch { /* ignore */ }
    bytes = 0;
  };
  wipe(); // on construction = engine start = reboot / update / restart

  const folderDir = (folderKey) => path.join(dir, encodeURIComponent(folderKey));
  const cachePath = (folderKey, file) => path.join(folderDir(folderKey), safeName(file));

  // Is there budget to cache another file? Under the byte cap AND above the free-space floor. The cap
  // is soft (a file in flight may cross it by one file), which is fine for a bounded session buffer.
  function underBudget() {
    if (bytes >= CAP_BYTES) return false;
    try {
      const st = fs.statfsSync(dir);
      if (st.bavail * st.bsize < FLOOR_BYTES) return false;
    } catch { /* can't tell free space: the cap still bounds us, so allow */ }
    return true;
  }

  // Fetch one file from the Mac into the cache (atomic temp + rename). Returns the cached path or null.
  async function fetchToCache(folderKey, folderId, file, base) {
    const url = `${base}/folder-media/${folderId}/${encodeURIComponent(file)}`;
    let res;
    try { res = await fetch(url, { signal: AbortSignal.timeout(20000) }); }
    catch { return null; }
    if (!res || !res.ok || !res.body) return null;
    try { await fsp.mkdir(folderDir(folderKey), { recursive: true }); } catch { /* ignore */ }
    const dest = cachePath(folderKey, file);
    const tmp = `${dest}.tmp-${process.pid}-${Date.now()}`;
    try {
      await new Promise((resolve, reject) => {
        Readable.fromWeb(res.body).pipe(fs.createWriteStream(tmp)).on('finish', resolve).on('error', reject);
      });
      const size = (await fsp.stat(tmp)).size;
      await fsp.rename(tmp, dest);
      bytes += size;
      return dest;
    } catch {
      try { await fsp.unlink(tmp); } catch { /* ignore */ }
      return null;
    }
  }

  async function baseForKey(folderKey) {
    const p = parseFolderKey(folderKey);
    if (!p) return null;
    try { return await resolveBase(p.hostId, p.folderId); } catch { return null; }
  }

  return {
    // Mark which remote folder is live; on a CHANGE, wipe the previous folder's cache (leaving folder
    // mode or switching folders, §17). Only one folder is ever active (the either/or), so a wipe is the
    // whole cache. Idempotent, so /api/display can call it every poll.
    setActive(folderKey) {
      if (folderKey === activeKey) return;
      wipe();
      activeKey = folderKey;
    },
    clear() { wipe(); activeKey = null; },
    usage() { return { bytes, capBytes: CAP_BYTES }; },

    // Ensure a file is cached if there is budget (the prefetch worker, CP4b). Best-effort, no throw.
    async warm(folderKey, folderId, file, base) {
      if (fs.existsSync(cachePath(folderKey, file))) return;
      if (!underBudget()) return; // over budget: leave the overflow to stream-through at play time
      await fetchToCache(folderKey, folderId, file, base);
    },

    // Serve a file for /folder-media on the frame. Returns { localPath } (from cache, or just cached),
    // { streamUrl } (over budget: proxy-stream the overflow), or null (Host unreachable / fetch failed).
    async get(folderKey, file) {
      const dest = cachePath(folderKey, file);
      try { if ((await fsp.stat(dest)).isFile()) return { localPath: dest }; } catch { /* cache miss */ }
      const p = parseFolderKey(folderKey);
      const base = p ? await baseForKey(folderKey) : null;
      if (!p || !base) return null; // Host not reachable right now
      if (underBudget()) {
        const cached = await fetchToCache(folderKey, p.folderId, file, base);
        return cached ? { localPath: cached } : null;
      }
      return { streamUrl: `${base}/folder-media/${p.folderId}/${encodeURIComponent(file)}` };
    },
  };
}

module.exports = { create };

'use strict';

// Folder Collections — Phase B (the frame side): a frame is a Display client that shows a folder
// living on a Mac Host, reached over the LAN (HANDOFF §17). This module turns the raw Bonjour host
// registry (src/discovery.js browse) into a list of selectable REMOTE folders by asking each
// discovered Host for its shared folders (GET /api/shared-folders, the open, path-free endpoint).
//
// It owns NO definition: the folder is defined once on the Mac; the frame only references it. A
// remote source is identified by a stable ref `remote:<hostId>:<folderId>` stored in display_source;
// the Host's current LAN address is resolved LIVE from discovery at use time (an IP can change), so
// the ref never pins an address. Best-effort throughout: an offline or old Host simply drops out of
// the list, never an error. No new dependencies (global fetch / AbortSignal.timeout, Node >= 22.5).

const SCHEME = 'remote:';

// The ref stored in display_source for a Host+folder. Opaque to the control panel (it is just an id
// in the Source dropdown); parsed back by parseRef().
function makeRef(hostId, folderId) { return `${SCHEME}${hostId}:${folderId}`; }

function parseRef(ref) {
  if (typeof ref !== 'string' || !ref.startsWith(SCHEME)) return null;
  const rest = ref.slice(SCHEME.length);
  const i = rest.indexOf(':');
  if (i < 0) return null;
  const hostId = rest.slice(0, i);
  const folderId = Number(rest.slice(i + 1));
  if (!hostId || !Number.isInteger(folderId)) return null;
  return { hostId, folderId };
}

// The base URL to reach a discovered Host. Prefer an IPv4 address (link-local IPv6 needs a scope id
// we do not have); fall back to the next address, then to `<host>.local` (mDNS) when the address list
// is empty (some Hosts advertise the service without inline A records, seen in the CP1 on-network
// check). Uses the advertised port.
function baseFor(host) {
  const port = host.port || 80;
  const addrs = Array.isArray(host.addresses) ? host.addresses : [];
  const ipv4 = addrs.find((a) => /^\d+\.\d+\.\d+\.\d+$/.test(a));
  const addr = ipv4 || addrs[0] || (host.host ? `${host.host}.local` : null);
  if (!addr) return null;
  const hostpart = addr.includes(':') ? `[${addr}]` : addr; // bracket an IPv6 literal
  return `http://${hostpart}:${port}`;
}

// Fetch one Host's shared folders. Returns [] on ANY failure (offline, old version without the
// endpoint, non-JSON, timeout), so one bad Host never breaks the assembled list.
async function fetchShared(host) {
  const base = baseFor(host);
  if (!base) return [];
  try {
    const res = await fetch(`${base}/api/shared-folders`, { signal: AbortSignal.timeout(2500) });
    if (!res.ok) return [];
    const body = await res.json();
    const list = Array.isArray(body && body.folders) ? body.folders : [];
    const hostName = host.name || (body.host && body.host.name) || 'a Mac';
    return list.map((f) => ({
      ref: makeRef(host.id, f.id),
      hostId: host.id,
      hostName,
      base,                 // resolved fresh each refresh, so a changed IP is picked up
      folderId: f.id,
      name: f.name,
      artist: f.artist,
      fit: f.fit,
      order: f.order,
      count: f.count,
      reachable: f.reachable !== false,
    }));
  } catch {
    return [];
  }
}

// A frame's live view of the folders served by other Hosts. `hostsProvider` returns the current
// Bonjour registry (discovery.browse().list()); a short TTL cache keeps the control panel's frequent
// polls from hammering the LAN.
function create({ hostsProvider, ttlMs = 4000 } = {}) {
  let cache = { at: 0, folders: [] };
  let inflight = null;

  async function refresh() {
    const hosts = (typeof hostsProvider === 'function' ? hostsProvider() : []) || [];
    const results = await Promise.all(hosts.map(fetchShared));
    cache = { at: Date.now(), folders: results.flat() };
    return cache.folders;
  }

  // The remote folders visible right now. Serves the cache within the TTL, refreshes past it, and on
  // a failed refresh keeps the last-known list. Never throws.
  async function list() {
    if (Date.now() - cache.at < ttlMs) return cache.folders;
    if (!inflight) inflight = refresh().catch(() => cache.folders).finally(() => { inflight = null; });
    return inflight;
  }

  // Resolve a display_source ref to its remote-folder record (or null) for playback and validation.
  async function resolve(ref) {
    if (!parseRef(ref)) return null;
    const folders = await list();
    return folders.find((f) => f.ref === ref) || null;
  }

  return { list, resolve };
}

module.exports = { create, makeRef, parseRef, baseFor, SCHEME };

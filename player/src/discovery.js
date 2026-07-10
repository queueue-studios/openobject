'use strict';

// Bonjour / mDNS advertisement for the Host role (HANDOFF §20, 2026-07-01; MAC-APP-PLAN §A2).
//
// Announces THIS Host on the local network as an `_openobject._tcp` service so a Display or Control
// client (a Mac app, a future Apple TV) can find it without being told an address. One code path
// runs on both the frame and a Mac. On the frame this sits ALONGSIDE Avahi's existing hostname
// advertisement (openobject.local): Avahi advertises the host A record, we advertise the SERVICE
// record, which are different mDNS record types, so they coexist.
//
// Strictly additive and off the playback path. Advertising is best-effort: any failure to publish
// is logged and swallowed so it can NEVER block startup or take down the player. If the network
// forbids multicast, or the dependency is somehow missing, the Host still serves normally; it just
// isn't auto-discoverable, exactly as it was before this seam existed.
//
// Uses `bonjour-service` (pure JS, no native module, no build step; consistent with node:sqlite and
// the no-build-step ethos). The same library later does the browsing side for the Mac app.

// Published as `_openobject._tcp`. bonjour-service adds the leading underscore and the `_tcp`.
const SERVICE_TYPE = 'openobject';

// Advertise this Host. Returns a handle with .stop() to withdraw the record on shutdown. Never
// throws: on any error it logs and returns a no-op handle so callers need no try/catch.
function advertise({ name, port, id, version }) {
  let bonjour = null;
  try {
    const { Bonjour } = require('bonjour-service');
    // The SECOND constructor argument is the error handler for the underlying mDNS socket. Without
    // it, bonjour-service RE-THROWS async socket errors (e.g. `send EHOSTUNREACH` when the network
    // forbids multicast), which would crash the player. Passing a handler keeps advertising truly
    // best-effort: a network that can't multicast just means "not discoverable", never a crash.
    bonjour = new Bonjour(undefined, (err) => console.warn('[discovery] mDNS socket error (continuing without discovery):', err && err.message));
    const service = bonjour.publish({
      name,
      type: SERVICE_TYPE,
      port,
      // TXT records let a client read who this is straight from discovery, no follow-up call needed.
      // Same fields as /api/identity so the two never disagree.
      txt: { id: String(id), name: String(name), version: String(version), role: 'host' },
    });
    service.on('error', (err) => console.warn('[discovery] advertise error:', err && err.message));
    console.log(`[discovery] advertising "${name}" as _${SERVICE_TYPE}._tcp on port ${port}`);
  } catch (err) {
    console.warn('[discovery] Bonjour advertisement unavailable, continuing without it:', err && err.message);
    bonjour = null;
  }

  return {
    stop() {
      if (!bonjour) return;
      try {
        // Withdraw the record cleanly (a "goodbye") so clients don't briefly see a dead Host.
        bonjour.unpublishAll(() => {
          try { bonjour.destroy(); } catch { /* already gone */ }
        });
      } catch (err) {
        console.warn('[discovery] stop error:', err && err.message);
      }
    },
  };
}

// Browse for OTHER Hosts on the LAN — the client side of discovery (a frame finding the Mac that
// serves a Folder Collection, HANDOFF §17 Phase B; later the Mac app finding frames). Keeps a live
// registry of discovered `_openobject._tcp` services keyed by their mDNS instance name (fqdn),
// carrying the identity from the TXT records (id/name/version/role). Excludes THIS host by its id so
// a Host never lists itself. Best-effort and crash-proof exactly like advertise(): any failure logs
// and leaves an empty registry, never throws. Returns a handle with .list() and .stop().
function browse({ selfId } = {}) {
  let bonjour = null;
  let browser = null;
  const seen = new Map(); // fqdn -> { id, name, version, role, host, port, addresses, fqdn, lastSeen }

  const shape = (service) => {
    const txt = service.txt || {};
    return {
      id: txt.id ? String(txt.id) : null,
      name: txt.name ? String(txt.name) : (service.name || null),
      version: txt.version ? String(txt.version) : null,
      role: txt.role ? String(txt.role) : null,          // the TXT's architecture role (usually 'host')
      host: service.host || null,
      port: service.port || null,
      addresses: Array.isArray(service.addresses) ? service.addresses : [],
      fqdn: service.fqdn || null,
      lastSeen: Date.now(),
    };
  };

  try {
    const { Bonjour } = require('bonjour-service');
    // Same second-arg error handler as advertise(): without it, an async mDNS socket error (e.g. a
    // network that forbids multicast) would be re-thrown and crash the player.
    bonjour = new Bonjour(undefined, (err) => console.warn('[discovery] mDNS socket error (continuing without discovery):', err && err.message));
    browser = bonjour.find({ type: SERVICE_TYPE });
    browser.on('up', (service) => {
      try {
        const rec = shape(service);
        if (selfId && rec.id && rec.id === String(selfId)) return; // never list ourself
        if (!rec.fqdn) return;
        seen.set(rec.fqdn, rec);
        console.log(`[discovery] found "${rec.name}" at ${rec.addresses[0] || rec.host || '?'}:${rec.port}`);
      } catch (err) {
        console.warn('[discovery] browse (up) error:', err && err.message);
      }
    });
    browser.on('down', (service) => {
      if (service && service.fqdn && seen.delete(service.fqdn)) {
        console.log(`[discovery] host gone: ${service.fqdn}`);
      }
    });
    browser.on('error', (err) => console.warn('[discovery] browse error:', err && err.message));
    console.log(`[discovery] browsing for _${SERVICE_TYPE}._tcp hosts on the LAN`);
  } catch (err) {
    console.warn('[discovery] Bonjour browse unavailable, continuing without it:', err && err.message);
    bonjour = null;
  }

  return {
    // A snapshot of the currently-visible Hosts (excluding self). Never throws.
    list() {
      return [...seen.values()];
    },
    // Stop browsing and release the socket. Never throws.
    stop() {
      try { if (browser && typeof browser.stop === 'function') browser.stop(); } catch { /* ignore */ }
      try { if (bonjour) bonjour.destroy(); } catch { /* ignore */ }
      bonjour = null;
    },
  };
}

module.exports = { advertise, browse, SERVICE_TYPE };

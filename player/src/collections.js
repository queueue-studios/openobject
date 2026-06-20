'use strict';

// Connected collections: the curated registry of supported web/on-chain art
// collections, plus the add-time resolver and the local mirror of each collection's shared
// render bundle.
//
// Model: the owner never authors a collection. Each entry below is a hand-coded, vetted
// collection. Adding a piece = pick the collection + enter its Token ID; we read the token's
// on-chain `tokenURI` to find its canonical metadata, take the official `animation_url`
// VERBATIM (never a marketplace render), mirror the shared bundle locally, and from then on it
// plays offline like any other Library piece. New collections arrive as code, not from users.

const path = require('path');
const fs = require('fs');
const db = require('./db');

const COLLECTIONS_DIR = path.join(db.DATA_DIR, 'collections');

// ── The supported list (shipped in code; grows as more are hand-coded) ──
const REGISTRY = [
  {
    slug: 'azulejo-galo',
    artist: 'Bryan Brinkman',
    name: 'Azulejo Galo',
    chain: 'Ethereum',
    contract: '0x61d115f1a3b08f871A1171041C9AF5bb5f747e47',
    // One free read call (tokenURI) goes through a public Ethereum node. Swappable; many exist.
    rpc: 'https://ethereum-rpc.publicnode.com',
    // This collection animates on load via its global toggleRotation() (its "Toggle Rotation" menu).
    animateDefault: true,
  },
  {
    slug: 'as-the-days-go-by',
    artist: 'Alex Kittoe',
    name: 'As the Days Go By',
    chain: 'Ethereum',
    contract: '0x9a9b9b14581136cb2f0f53e2b65ba6c74fd660b4',
    rpc: 'https://ethereum-rpc.publicnode.com',
    // A time-aware still, not a generative sketch: the bundle itself swaps a day or night photo
    // from the viewer's local clock (day = 6am-6pm), rechecking each minute. Nothing to engage on
    // load, so this collection has no Animate control (animatable: false).
    animateDefault: false,
    animatable: false,
  },
  {
    slug: 'send-receive',
    artist: 'Erick Calderon (Snowfro)',
    name: 'send/receive',
    chain: 'Ethereum',
    contract: '0xababababab20053426ad1c782de9ea8444358070',
    rpc: 'https://ethereum-rpc.publicnode.com',
    // A LIVE, networked artwork (Art Blocks Flex on-chain). Unlike the self-contained pieces above,
    // each token's generator HTML reads the global on-chain state of the whole collection at display
    // time (block by block, the send/receive balance across all tokens) and animates from it. So:
    //  • perToken: the generator returns a different fully-inlined HTML per token (token id in the
    //    path, no query seed), so each token gets its own mirrored bundle, not a shared one.
    //  • liveRpc: the piece needs a reachable Ethereum RPC to animate. We override its embedded
    //    endpoint with our own swappable public node (display.js appends ?rpc_url=) and scope a
    //    connect-src exception to just this collection's bundle path (server.js). Offline it falls
    //    back to a static sprite with the artist's own network-error badge, so this is the one
    //    collection that is not fully offline. It self-animates with live data, so no Animate toggle.
    perToken: true,
    liveRpc: true,
    animateDefault: false,
    animatable: false,
    // The generator composes the artwork in the centered 60% of the panel with a 20% black margin
    // on every side. We want it edge to edge (HANDOFF §6, no border), so the display zooms the iframe
    // to crop that margin out. `crop` is the centered fraction the art occupies; 0.6 -> 1/0.6 zoom.
    // Measured off the static "white version" of the sprite card, constant across this collection.
    crop: 0.6,
  },
  {
    slug: 'dune-reveries-editions',
    artist: 'Juicy Julio',
    name: 'Dune Reveries - Editions',
    chain: 'Ethereum',
    contract: '0x45dcaec1c3c51148771a7a32669ea0adab051b3e',
    rpc: 'https://ethereum-rpc.publicnode.com',
    // ERC-1155, not ERC-721: the metadata location is read from uri(uint256), not tokenURI.
    erc1155: true,
    // The collection holds three editions, but only "Golden Lining" (token 1) needs special handling
    // (the other two are plain static images). So we support exactly token 1 and skip the Token-ID
    // prompt — the add flow uses fixedToken (still resolved on-chain, for faithfulness).
    fixedToken: '1',
    // A p5.js sketch over a single landscape JPEG: each frame it draws the photo, greys the whole
    // canvas, then redraws the same photo in colour on top at a variable opacity — a global
    // b&w<->colour crossfade the artist drives with mouse-X. We never feed input; a fluid cosine
    // sweep drives that global `opacity` itself (SPEED_HOOK). A 0..10 speed (0 = static full colour)
    // replaces the on/off Animate control for this collection.
    speedControl: true,
    speedDefault: 2,
    // The photo is 5:4 landscape; declaring its aspect lets the display size the iframe to the piece
    // and letterbox it against the bare black stage natively — no white padding, no zoom-crop (§6).
    aspect: '2124 / 1698',
    // p5 (cdnjs) and the JPEG (ipfs.io) are absolute URLs, and the image refs live inside an inline
    // script (loadImage('…')) the generic relative-asset scan can't see. Localize downloads every
    // absolute http(s) asset into the bundle and rewrites the refs, so it plays fully offline.
    localizeAbsolute: true,
    // The token's official `image` is a stylised half-grey/half-colour split preview; show a
    // full-colour thumbnail (the master photo the sketch loads) instead, matching the rest state.
    thumbFromAnimationImage: true,
  },
  {
    slug: 'perfect-everything',
    artist: 'V4w.enko',
    name: 'Perfect Everything',
    chain: 'Tezos',
    contract: 'KT1AvGKGryeASE9PXbm345dgPUxVETDLx8qX',
    // First Tezos collection, so the resolve trail differs from the Ethereum ones above: Tezos has no
    // eth_call / tokenURI. We read the token's FA2 metadata (artifactUri + displayUri) from the TzKT
    // public indexer API (one free GET, swappable like an `rpc`). If TzKT is ever unavailable, a
    // refactor can read the contract's token_metadata big_map straight from a public Tezos RPC node
    // instead (see HANDOFF §20); either way the official artifactUri is what we store verbatim.
    tzkt: 'https://api.tzkt.io',
    // A self-contained p5.js EditART sketch (p5 inlined, no external assets). The per-edition seed
    // rides in the artifactUri query string (m0..m4), so the whole collection shares one bundle and
    // the owner just enters their Token ID, same shape as Azulejo. The square canvas (min(w,h)) fills
    // our square stage edge to edge (no crop, no aspect), and draw() loops continuously on its own, so
    // there is nothing to engage on load: no Animate control.
    animateDefault: false,
    animatable: false,
  },
  {
    slug: 'pendulum',
    artist: 'Cinzia y Gabriel',
    name: 'Pendulum',
    chain: 'Tezos',
    contract: 'KT1FxLAch681RsZ2UYoSNQ5S5xsgT6mFHwZq',
    // Second Tezos collection, resolved exactly like Perfect Everything: no eth_call / tokenURI, so the
    // token's FA2 metadata (artifactUri + displayUri) is read from the TzKT public indexer API off a
    // swappable `tzkt` base. The same token_metadata big_map fallback applies (HANDOFF §20).
    tzkt: 'https://api.tzkt.io',
    // A self-contained p5.js EditART series (p5 inlined, no external assets), the same shape as Perfect
    // Everything: the per-edition seed rides in the artifactUri query (m0..m4), so the whole collection
    // shares one bundle and the owner enters their Token ID (any edition resolves; no fixedToken). The
    // square canvas (min(w,h)) fills the 1:1 stage edge to edge (no crop, no aspect), and draw() loops
    // continuously on its own, so there is nothing to engage on load: no Animate control.
    animateDefault: false,
    animatable: false,
  },
  {
    slug: 'lost-in-moffat-county',
    artist: 'Jeremy Booth',
    name: 'Lost in Moffat County',
    chain: 'Ethereum',
    contract: '0x98a8ae5ea04a7cff60cd4877a6e97eb2113b111e',
    rpc: 'https://ethereum-rpc.publicnode.com',
    // ERC-721 tokenURI, but each token's metadata points to its OWN media bundle (hosted on Arweave or
    // IPFS, mixed across the collection) with its own day/night/easter assets, so each token mirrors into
    // its own dir (perToken, like send/receive) rather than sharing one. The owner enters a Token ID.
    perToken: true,
    // The bundle loads p5 (cdnjs) and its day/night photos + easter-egg GIFs by ABSOLUTE URL (a Pinata
    // gateway) from inside inline loadImage() calls, so localize them into the bundle and rewrite the refs
    // for offline play (the Golden Lining mechanism).
    localizeAbsolute: true,
    // A time-aware p5 piece (like Kittoe): each draw it reads the viewer's LOCAL clock and crossfades a
    // day photo into a night photo (sunrise 6-8, sunset 18-20), so the background is chosen automatically
    // with no app timezone UI (correctness = the frame's OS clock). It also has a click "easter egg": a tap
    // toggles a global `easterEgg` flag that swaps in an animated GIF overlay (also day/night aware). That
    // is our optional Animate, default OFF (background only), engaged hands-free by the easterEgg hook below.
    animateDefault: false,
    animateHook: 'easterEgg',
    // The photos are square (3840^2 / 2500^2) drawn object-fit: contain, so on the 1:1 stage they fill edge
    // to edge (no crop, no aspect). Token 1 ("Desert Steel") is a static landscape image with no
    // animation_url and is intentionally NOT supported here (it resolves with a clear "no artwork URL"
    // error); it can be added as a normal upload if ever wanted.
  },
  {
    slug: 'perfect-circles',
    artist: 'V4w.enko',
    name: 'Perfect Circles',
    chain: 'Tezos',
    contract: 'KT1RtgaTm3P35uNzrD2RZPtRwFVCKmjMUbUh',
    // A second EditART series from the same artist as Perfect Everything, the same Tezos shape, so it
    // reuses the Tezos branch in readTokenMeta with no new mechanics: TzKT resolves the FA2 metadata
    // (artifactUri + displayUri), one shared p5 bundle carries the per-edition seed (m0..m4) in the
    // query string (10 editions; the owner enters their Token ID), and the square self-looping canvas
    // fills the 1:1 stage edge to edge. No crop/aspect, no Animate control.
    tzkt: 'https://api.tzkt.io',
    animateDefault: false,
    animatable: false,
  },
  {
    slug: 'chazstract',
    artist: 'Chaz Wesley',
    name: 'Chazstract',
    chain: 'Tezos',
    contract: 'KT1AATmFFJtPrmpnfdaTcFB1ojhdNJmd92C2',
    // "Chazstract" is the artist's general objkt.com contract: every token is a DIFFERENT artwork, not a
    // seeded series, so (like Golden Lining within "Dune Reveries") we support just the one vetted piece,
    // token 28, "The Bloom". fixedToken skips the Token-ID prompt (still resolved on-chain for faithfulness).
    tzkt: 'https://api.tzkt.io',
    fixedToken: '28',
    // The artifactUri is a bare IPFS *directory* CID whose index.html pulls p5.min.js + p5.sound.min.js +
    // the music file by RELATIVE ref, so the mirror takes the asset base from the directory itself
    // (dirBundle), not the gateway root.
    dirBundle: true,
    // The bundle also loads p5.sound.min.js, which the sketch never actually uses (its audio is raw Web
    // Audio), and that unused library hangs the renderer in restricted contexts (it froze p5 before setup()
    // in a headless browser). We are always muted (§12), so we drop it from the mirror: the visual is
    // identical and now renders reliably everywhere. (The desktop archival copy keeps it, faithfully.)
    dropScripts: ['p5.sound.min.js'],
    // A fixed 1920x1080 (16:9) canvas the sketch self-fits to the viewport on black. Declaring the aspect
    // letterboxes it on the bare square stage (Golden Lining-style); on a 16:9 screen it fills edge to edge.
    aspect: '1920 / 1080',
    // The piece opens behind a "Click to Bloom" overlay that also gates the bloom; a passive frame can't
    // click, so the bloom hook auto-starts it on every display, silently (the music never plays, §12). It
    // self-animates after that (flowers sway and spin on their own, a spaceship drifts), so no Animate
    // toggle. Its hand interactions (click a flower to spin, the music panel) are not supported on a passive,
    // muted frame.
    animateDefault: false,
    animatable: false,
    animateHook: 'bloom',
  },
  {
    slug: 'code-art',
    artist: 'NFTman76',
    name: 'Code art',
    chain: 'Ethereum',
    contract: '0xe2fe3818c305dfc2d2b9b4646bee95c050b0baf3',
    rpc: 'https://ethereum-rpc.publicnode.com',
    // "Code art" is the artist's general contract where every token is a DIFFERENT artwork, so (like
    // Golden Lining within "Dune Reveries" and "The Bloom" within "Chazstract") we support just the one
    // vetted piece, token 17, "Binary Mountains" — a three.js wireframe-mountains scene with falling
    // snow. fixedToken skips the Token-ID prompt (still resolved on-chain via tokenURI for faithfulness).
    fixedToken: '17',
    // The scene is otherwise a single self-contained HTML file but loads three.js by ABSOLUTE URL
    // (cdnjs), so localize that one script into the bundle and rewrite the ref for offline play (the
    // Golden Lining / Lost in Moffat County mechanism).
    localizeAbsolute: true,
    // The camera orbits and the snow falls on their own (the piece has its own requestAnimationFrame
    // loop), so there is nothing to engage on load: no Animate control. What it DOES expose is snowfall
    // intensity — a global snowLevel (0..3) the artist cycles by tap. We surface that as the first
    // CHOICE control (a curated dropdown) instead: the display passes the chosen value as ?oochoice=N,
    // and the snow hook reaches that level by calling the artwork's own onClick() N times (snowLevel
    // starts at 0, so N taps land on level N — the faithful equivalent of the artist's tap). Values are
    // the artist's level indices; we expose the artist's full set (Light/Moderate/Heavy/Blizzard). The
    // choice plumbing (db column, API field, ?oochoice, this dropdown) is a reusable seam; only the
    // per-collection hook below is piece-specific.
    animateDefault: false,
    animatable: false,
    choice: {
      label: 'Snow',
      default: '0',
      options: [
        { value: '0', label: 'Light Snow' },
        { value: '1', label: 'Moderate Snow' },
        { value: '2', label: 'Heavy Snow' },
        { value: '3', label: 'Blizzard' },
      ],
    },
    choiceHook: 'snow',
    // The three.js scene is responsive (the camera aspect adapts to the viewport), so it has no inherent
    // shape. The artist's declared media is ~square (804x760), but on the square frame a filled square reads
    // as a cramped, stretched-looking crop of what is really a wide mountain vista, so we present it as a
    // LANDSCAPE image: a 16:9 `aspect` letterboxes it on the bare stage (the Golden Lining / The Bloom
    // pattern, HANDOFF §6) and the scene renders that wide vista undistorted. The snow hook also nudges a
    // resize after load so a responsive WebGL canvas can't latch onto a stale (stretched) size at load.
    aspect: '16 / 9',
  },
];

const bySlug = (slug) => REGISTRY.find((c) => c.slug === slug) || null;

// Some collections host metadata/bundles on IPFS, which Node's fetch can't dereference (ipfs:// is
// not http). Map ipfs:// to a public gateway for fetching only; the official ipfs:// URL is still
// what we store verbatim. Plain http(s) (e.g. Arweave) passes through unchanged. Gateway is swappable.
const IPFS_GATEWAY = 'https://ipfs.io/ipfs/';
const toHttp = (url) => {
  const s = String(url || '');
  return s.startsWith('ipfs://') ? IPFS_GATEWAY + s.slice(7).replace(/^ipfs\//, '') : s;
};

// Every outbound fetch below pulls from public RPC nodes and IPFS/Arweave gateways, which can stall
// (connect but never answer). Node's fetch has no timeout, so a dead source would otherwise hang the
// add/preview forever (the spinner that never returns). ooFetch puts one flat 30s ceiling on every
// call and turns a stall into a clean, surfaced error instead. It is a FAILURE ceiling, not an
// expected wait: the happy path is seconds, and 30s only bites when a source is genuinely stuck
// (HANDOFF §8/§20). Hardcoded by choice — one number, generous enough that it should never need tuning.
const FETCH_TIMEOUT_MS = 30000;
async function ooFetch(url, opts) {
  try {
    return await fetch(url, { ...opts, signal: AbortSignal.timeout(FETCH_TIMEOUT_MS) });
  } catch (e) {
    if (e && (e.name === 'TimeoutError' || e.name === 'AbortError')) {
      let host = String(url);
      try { host = new URL(url).host; } catch { /* keep the raw string */ }
      throw new Error(`Timed out reaching ${host} after ${FETCH_TIMEOUT_MS / 1000}s.`);
    }
    throw e;
  }
}

// ── On-chain resolve: Token ID → official animation_url (+ title, preview) ──
// tokenURI(uint256) (ERC-721) and uri(uint256) (ERC-1155) are both a free `eth_call` (no gas, no
// wallet) returning the token's canonical metadata location — the source of truth, not a render.
async function ethCallTokenURI(c, tokenId) {
  const selector = c.erc1155 ? '0x0e89341c' : '0xc87b56dd'; // uri(uint256) | tokenURI(uint256)
  const data = selector + BigInt(tokenId).toString(16).padStart(64, '0');
  const r = await ooFetch(c.rpc, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'eth_call', params: [{ to: c.contract, data }, 'latest'] }),
  });
  if (!r.ok) throw new Error(`Ethereum node returned ${r.status}.`);
  const j = await r.json();
  if (j.error) {
    // A reverting tokenURI/uri(id) means the token doesn't exist (ERC-721/1155 revert on an unknown id).
    // Surface the same plain message as an empty result, not the node's raw "execution reverted"; keep
    // genuine node errors (timeouts, rate limits) honest so a network hiccup isn't mislabeled "no such token".
    const reverted = j.error.code === 3 || /revert/i.test(j.error.message || '');
    throw new Error(reverted ? 'No such token (check the Token ID).' : (j.error.message || 'Ethereum read failed.'));
  }
  const hex = (j.result || '').replace(/^0x/, '');
  if (hex.length < 128) throw new Error("No such token (check the Token ID).");
  const len = parseInt(hex.slice(64, 128), 16);            // ABI string: [offset][length][bytes]
  let str = Buffer.from(hex.slice(128, 128 + len * 2), 'hex').toString('utf8');
  if (!str) throw new Error('That token has no metadata URL.');
  // ERC-1155 may return a templated URI with an {id} placeholder (lowercase, zero-padded hex).
  if (c.erc1155 && str.includes('{id}')) str = str.replace(/\{id\}/g, BigInt(tokenId).toString(16).padStart(64, '0'));
  return str;
}

// Find the first image a bundle's HTML references: a p5 loadImage('…') first, else any absolute URL
// with an image extension. Lets a collection source a full-colour thumbnail from the artwork itself
// (e.g. when the token's official `image` is a stylised preview we don't want to show).
function firstImageUrl(html) {
  const s = String(html);
  const m = s.match(/loadImage\(\s*['"]([^'"]+)['"]/);
  if (m) return m[1];
  const u = s.match(/https?:\/\/[^\s"'`<>()]+\.(?:jpe?g|png|gif|webp|avif)/i);
  return u ? u[0] : null;
}

// Read a token's canonical metadata per chain, normalised to { meta, sourceUrl, image }.
// Ethereum: tokenURI/uri(id) (above) → a metadata JSON carrying animation_url + image.
// Tezos (FA2): no eth_call. Read the token's metadata from the TzKT public indexer API, which
// surfaces the contract's own token_metadata (artifactUri + displayUri/thumbnailUri) in one free
// GET. Swappable like an rpc; if TzKT is ever unavailable, a refactor can read the token_metadata
// big_map straight from a public Tezos RPC node (HANDOFF §20). Either way the official URL is verbatim.
async function readTokenMeta(c, tid) {
  if (c.chain === 'Tezos') {
    const url = `${c.tzkt}/v1/tokens?contract=${encodeURIComponent(c.contract)}&tokenId=${encodeURIComponent(tid)}`;
    const r = await ooFetch(url);
    if (!r.ok) throw new Error(`Tezos indexer returned ${r.status}.`);
    const arr = await r.json();
    const meta = (Array.isArray(arr) && arr[0] && arr[0].metadata) || null;
    if (!meta) throw new Error('No such token (check the Token ID).');
    return { meta, sourceUrl: meta.artifactUri, image: meta.displayUri || meta.thumbnailUri || null };
  }
  const metaUrl = await ethCallTokenURI(c, tid);                 // Ethereum → metadata location
  const mr = await ooFetch(toHttp(metaUrl));                        // metadata may live on IPFS
  if (!mr.ok) throw new Error(`Couldn't read the token metadata (${mr.status}).`);
  const meta = await mr.json();
  return { meta, sourceUrl: meta.animation_url, image: meta.image || null };
}

// Returns { tokenId, title, sourceUrl (verbatim official URL), image (preview, may be null) }.
async function resolveToken(slug, tokenId) {
  const c = bySlug(slug);
  if (!c) throw new Error('Unknown collection.');
  // fixedToken collections support exactly one piece, so the add flow need not send a Token ID.
  const tid = String((tokenId == null || tokenId === '') ? (c.fixedToken || '') : tokenId).trim();
  if (!/^\d+$/.test(tid)) throw new Error('Token ID must be a number.');
  const { meta, sourceUrl, image: previewImage } = await readTokenMeta(c, tid); // chain-aware read
  if (!sourceUrl) throw new Error('This token has no artwork URL in its metadata.');
  let image = previewImage;
  // Prefer the artwork's own image over a stylised official preview (e.g. Golden Lining's split
  // half-grey/half-colour `image`): pull the first image the bundle loads and use that instead.
  if (c.thumbFromAnimationImage) {
    try { const img = firstImageUrl(await (await ooFetch(toHttp(sourceUrl))).text()); if (img) image = img; } catch { /* keep meta.image */ }
  }
  return { tokenId: tid, title: meta.name || `${c.name} #${tid}`, sourceUrl, image };
}

// ── Mirror the shared render bundle once, served same-origin (server CSP allows it to run and
// be framed by the display). Lets us inject the auto-animate hook and play with no network later. ──
function bundleDir(slug) { return path.join(COLLECTIONS_DIR, slug); }

// Where a piece's bundle lives. Most collections share one bundle for the whole collection (the
// per-piece seed rides in the source URL's query string). `perToken` collections (Art Blocks-style)
// return a different fully-inlined HTML per token, so each token gets its own dir under the slug.
function outDir(slug, tokenId) {
  const c = bySlug(slug);
  return c && c.perToken ? path.join(bundleDir(slug), String(tokenId)) : bundleDir(slug);
}
function isMirrored(slug, tokenId) { return fs.existsSync(path.join(outDir(slug, tokenId), 'index.html')); }

// Live (networked) collections read a public RPC at display time (e.g. send/receive reads the
// global on-chain state that drives its animation). We scope a connect-src exception to just that
// collection's bundle path; every other collection stays locked to same-origin. Given a request
// path under /collections (e.g. "/send-receive/5008760/index.html"), return the RPC origin to
// allow, or null. The artwork's embedded endpoint is overridden at render time with our own
// swappable public node, so only this one origin needs allowing (no reliance on the embedded key).
function liveRpcForPath(reqPath) {
  const seg = decodeURIComponent(String(reqPath || '').replace(/^\/+/, '').split('/')[0] || '');
  const c = bySlug(seg);
  if (!c || !c.liveRpc) return null;
  try { return new URL(c.rpc).origin; } catch { return null; }
}

// Injected into the mirrored index.html: when the iframe is opened with ?ooanim=1, wait until the
// sketch has generated, then fire its global animate function ONCE (Azulejo: toggleRotation).
const ANIMATE_HOOK = `
<script>
(function(){
  if (new URLSearchParams(location.search).get('ooanim') !== '1') return;
  var fired = false, n = 0;
  var iv = setInterval(function(){
    if (fired || ++n > 300) { clearInterval(iv); return; }   // ~30s safety
    try {
      if (typeof toggleRotation === 'function'
          && typeof ROT_ACTIVE !== 'undefined' && !ROT_ACTIVE
          && typeof ROT_TILES !== 'undefined' && ROT_TILES
          && ROT_TILES.filter(function(t){ return t.snapshot; }).length > 0) {
        fired = true; clearInterval(iv); toggleRotation();
      }
    } catch (e) {}
  }, 100);
})();
</script>`;

// Injected into a speedControl collection's mirror: drive the sketch's global b&w<->colour amount
// (`window.opacity`, 0..100) with a fluid cosine sweep so the piece animates hands-free, no input.
// The speed 0..10 rides in on ?oospeed=N (display.js): 0 holds full colour, 1..10 set the round-trip
// pace. A cosine eases in/out at both turns (velocity 0 at the extremes) and never stops or jumps,
// and is anchored on full colour (phase 0 -> opacity 100). With no ?oospeed the artwork is untouched
// (it keeps its original mouse interaction).
const SPEED_HOOK = `
<script>
(function(){
  var sp = parseFloat(new URLSearchParams(location.search).get('oospeed'));
  if (isNaN(sp)) return;
  sp = Math.max(0, Math.min(10, sp));
  var clamp = function(v){ return Math.max(0, Math.min(100, v)); };
  if (sp <= 0) { setInterval(function(){ window.opacity = 100; }, 16); return; } // rest: full colour
  var TWO_PI = Math.PI * 2, cycleMs = 48000 / sp, phase = 0, last = null;
  requestAnimationFrame(function f(t){
    requestAnimationFrame(f);
    if (last === null) last = t;
    phase += ((t - last) / cycleMs) * TWO_PI; last = t;
    if (phase >= TWO_PI) phase -= TWO_PI;
    window.opacity = clamp(50 + 50 * Math.cos(phase));
  });
})();
</script>`;

// Injected into "Lost in Moffat County" (Jeremy Booth): the piece is a time-aware day/night photo that
// also has a click "easter egg" (its touchEnded toggles a global `easterEgg`, swapping in an animated GIF
// overlay). With ?ooanim=1 (Animate on) we engage that overlay hands-free: wait until the sketch's setup()
// has run (it sets `easterEgg = false` once, after preload loads the images), then set it true ONCE. With
// no ?ooanim the piece is untouched, just the automatic time-of-day background.
const EASTER_HOOK = `
<script>
(function(){
  if (new URLSearchParams(location.search).get('ooanim') !== '1') return;
  var n = 0;
  var iv = setInterval(function(){
    if (++n > 300) { clearInterval(iv); return; }   // ~30s safety
    if (typeof window.easterEgg === 'boolean') { window.easterEgg = true; clearInterval(iv); }
  }, 100);
})();
</script>`;

// Injected into Chaz Wesley's "The Bloom" (Chazstract #28): the piece opens behind a "Click to Bloom"
// overlay (#startOverlay) whose click runs the sketch's startExperience(), which hides the overlay AND
// starts the bloom clock (its flowers stay frozen as buds until then). A passive frame has no one to click,
// so we fire it ourselves once setup() has run (the canvas exists). OpenObject is always muted (HANDOFF §12),
// so we no-op audio playback first; the garden then blooms and self-animates with no sound. Runs
// unconditionally: revealing the garden is required to display the art, not an optional Animate.
const BLOOM_HOOK = `
<script>
(function(){
  try { HTMLMediaElement.prototype.play = function(){ return Promise.resolve(); }; } catch (e) {}
  var n = 0;
  var iv = setInterval(function(){
    if (++n > 300) { clearInterval(iv); return; }   // ~30s safety
    if (typeof startExperience !== 'function' || !document.querySelector('canvas')) return;
    clearInterval(iv);
    try { startExperience(); } catch (e) {}
  }, 100);
})();
</script>`;

// Injected into NFTman76's "Binary Mountains" (Code art #17): the scene self-animates (orbiting camera,
// falling snow), but its snowfall intensity is a tap-cycled global snowLevel (0..3) applied by the
// artist's own onClick() (snowLevel = (snowLevel+1) % 4; updateSnowLevel()). We honor the owner's chosen
// level from ?oochoice=N by calling that same onClick() N times once it exists — snowLevel starts at 0,
// so N taps land on level N, the faithful equivalent of the artist's tap (snowLevel is a lexical `let`,
// not a window property, so it can't be assigned directly; onClick is a global function, so it can be
// called). We also hide the two on-screen overlays (the "tap to snow" prompt and the level pill) and
// nudge a resize after load (a responsive WebGL canvas can latch onto a stale iframe size and look
// stretched; re-firing the artwork's own resize handler re-fits it to the final letterboxed box): a
// passive frame can't tap, and the stage shows zero chrome (HANDOFF §6). Always injected; with no
// ?oochoice (or 0) only the overlays are hidden and the artwork keeps its Light Snow default.
const SNOW_HOOK = `
<script>
(function(){
  var s = document.createElement('style');
  s.textContent = '.info,.snow-level{display:none!important}';
  (document.head || document.documentElement).appendChild(s);
  // Re-fit to the final iframe size a few times after layout settles (guards a stale-size stretch).
  var refit = function(){ try { window.dispatchEvent(new Event('resize')); } catch (e) {} };
  [0, 150, 500, 1200, 2500].forEach(function(t){ setTimeout(refit, t); });
  window.addEventListener('load', refit);
  var n = parseInt(new URLSearchParams(location.search).get('oochoice'), 10);
  if (!(n > 0)) return;                                   // 0 / absent → the artwork's Light Snow default
  var tries = 0;
  var iv = setInterval(function(){
    if (++tries > 300) { clearInterval(iv); return; }     // ~30s safety
    if (typeof onClick !== 'function') return;            // wait until the artwork's script has run
    clearInterval(iv);
    for (var i = 0; i < n; i++) { try { onClick(); } catch (e) {} }
  }, 100);
})();
</script>`;

async function fetchBuf(url) {
  const r = await ooFetch(toHttp(url));
  if (!r.ok) throw new Error(`fetch ${url} → ${r.status}`);
  return Buffer.from(await r.arrayBuffer());
}

// Like fetchBuf but also returns the content-type, so a localized asset with no extension in its
// URL (e.g. an IPFS CID) can be given a sensible local filename.
async function fetchAsset(url) {
  const r = await ooFetch(toHttp(url));
  if (!r.ok) throw new Error(`fetch ${url} → ${r.status}`);
  return { buf: Buffer.from(await r.arrayBuffer()), ct: (r.headers.get('content-type') || '').split(';')[0].trim().toLowerCase() };
}

// Best-effort file extension for a localized asset whose URL has none, from the content-type and
// then magic bytes. Only used to name the local copy; the browser sniffs content for images anyway.
function extFor(ct, buf) {
  const byCt = { 'image/jpeg': '.jpg', 'image/png': '.png', 'image/gif': '.gif', 'image/webp': '.webp', 'image/avif': '.avif', 'application/javascript': '.js', 'text/javascript': '.js', 'text/css': '.css' }[ct];
  if (byCt) return byCt;
  if (buf && buf.length > 3) {
    if (buf[0] === 0xff && buf[1] === 0xd8) return '.jpg';
    if (buf[0] === 0x89 && buf[1] === 0x50) return '.png';
    if (buf[0] === 0x47 && buf[1] === 0x49) return '.gif';
  }
  return '';
}

// Mirror a piece's bundle, cleaning up a half-built dir if any fetch fails so a retry starts fresh.
async function mirrorBundle(slug, sourceUrl, tokenId) {
  const c = bySlug(slug);
  const out = outDir(slug, tokenId);                                         // per-token dir, or the shared bundle
  if (fs.existsSync(path.join(out, 'index.html'))) return;                   // already mirrored
  try {
    await mirrorInto(c, out, sourceUrl);
  } catch (e) {
    // A fetch timed out or the source died mid-mirror: drop the partial dir so the next add is clean
    // (index.html is written last, so a leftover dir without it would just be dead weight anyway).
    fs.rmSync(out, { recursive: true, force: true });
    throw e;
  }
}

// Fetch the entry HTML + every relative asset it references (scripts, etc.). For collections that
// expose an Animate control, inject the auto-animate hook; self-animating pieces are left verbatim.
async function mirrorInto(c, out, sourceUrl) {
  const u = new URL(toHttp(sourceUrl));                                      // ipfs:// → gateway for the fetch
  // A dirBundle collection's sourceUrl is a bare directory CID (ipfs://<cid>), whose index.html pulls its
  // assets by RELATIVE ref, so the asset base is the directory itself and the entry is its index.html.
  // Otherwise the path carries the file (or trailing dir) and base/entry come from the last path segment.
  const isDir = c && c.dirBundle;
  const dir = isDir ? u.pathname.replace(/\/?$/, '/') : u.pathname.slice(0, u.pathname.lastIndexOf('/') + 1); // .../<txid>/
  const base = u.origin + dir;
  const entry = isDir ? 'index.html' : (u.pathname.slice(u.pathname.lastIndexOf('/') + 1) || 'index.html');
  let html = (await fetchBuf(base + entry)).toString('utf8');
  // A public gateway may inject a tracking beacon (e.g. Cloudflare's hidden cdn-cgi <a>) into the
  // served HTML; it is not part of the artist's file, so strip it for a faithful mirror.
  html = html.replace(/<a\b[^>]*cdn-cgi[^>]*><\/a>/gi, '');
  // Drop any <script src> a collection flags as unwanted (e.g. The Bloom's unused p5.sound, which hangs the
  // renderer in restricted contexts; we are always muted). Removing the tag here, before the asset scan,
  // also stops the scan below from fetching it.
  if (c && Array.isArray(c.dropScripts)) for (const s of c.dropScripts) {
    const esc = s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    html = html.replace(new RegExp(`<script\\b[^>]*src=["']${esc}["'][^>]*>\\s*</script>`, 'gi'), '');
  }

  const assets = new Set();
  const re = /(?:src|href)=["']([^"']+)["']/gi;
  let m;
  while ((m = re.exec(html))) {
    const ref = m[1];
    if (/^(https?:)?\/\//i.test(ref) || ref.startsWith('data:') || ref.startsWith('#')) continue;
    assets.add(ref.replace(/^\.?\//, ''));
  }
  for (const rel of assets) {
    const buf = await fetchBuf(base + rel);
    const dest = path.join(out, rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, buf);
  }

  // Some collections reference assets by ABSOLUTE URL (a CDN script, an IPFS image), sometimes from
  // inside an inline script (loadImage('https://…')) the src/href scan above can't see. For those,
  // download every absolute http(s) asset into the bundle and rewrite the reference to a local file,
  // so the piece plays with no network. Gated per collection; others stay verbatim (still absolute).
  if (c && c.localizeAbsolute) {
    const urls = [...new Set(html.match(/https?:\/\/[^\s"'`<>()]+/gi) || [])];
    let n = 0;
    for (const url of urls) {
      let asset;
      try { asset = await fetchAsset(url); } catch { continue; }              // unreachable → leave as-is
      const tail = url.split(/[?#]/)[0].split('/').pop() || `asset-${n}`;
      const name = /\.[a-z0-9]{2,5}$/i.test(tail) ? tail : tail + extFor(asset.ct, asset.buf);
      fs.mkdirSync(out, { recursive: true });
      fs.writeFileSync(path.join(out, name), asset.buf);
      html = html.split(url).join(name);                                      // rewrite every occurrence
      n++;
    }
    // Subresource-integrity / crossorigin on a now-local script would fail or be pointless — drop them.
    html = html.replace(/\s+(?:integrity|crossorigin|referrerpolicy)=("[^"]*"|'[^']*')/gi, '');
  }

  // Inject the matching hook (engaged by ?oochoice / ?ooanim / ?oospeed at display time): a choice
  // collection gets its own control hook (snow → set the level + hide overlays); an easterEgg collection
  // gets the overlay-toggle hook; a speedControl collection gets the cosine sweep; other Animate-control
  // pieces get the fire-once hook. Self-animating / still pieces (Kittoe, send/receive) get none, verbatim.
  const hook = c && c.choiceHook === 'snow' ? SNOW_HOOK
    : c && c.animateHook === 'bloom' ? BLOOM_HOOK
    : c && c.animateHook === 'easterEgg' ? EASTER_HOOK
    : c && c.speedControl ? SPEED_HOOK
    : (c && c.animatable !== false ? ANIMATE_HOOK : '');
  if (hook) html = html.includes('</body>') ? html.replace('</body>', hook + '\n</body>') : html + hook;
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'index.html'), html, 'utf8');
}

// Remove a piece's mirrored bundle. perToken collections give each token its own bundle, so it is
// safe to delete on removal; shared-bundle collections keep theirs (other pieces may still use it).
function removeBundle(slug, tokenId) {
  const c = bySlug(slug);
  if (c && c.perToken) fs.rm(path.join(bundleDir(slug), String(tokenId)), { recursive: true, force: true }, () => {});
}

// Cache the preview image locally so the Library card has an offline thumbnail.
async function cacheThumb(slug, tokenId, imageUrl) {
  if (!imageUrl) return null;
  try {
    const rel = path.posix.join('thumbs', `${tokenId}.png`);
    const dest = path.join(bundleDir(slug), rel);
    fs.mkdirSync(path.dirname(dest), { recursive: true });
    fs.writeFileSync(dest, await fetchBuf(imageUrl));
    return `/collections/${slug}/${rel}`;
  } catch { return imageUrl; } // fall back to the remote preview if caching fails
}

// Fetch an image and return it as a data: URL. Used for the add-flow preview, which renders under
// the control panel's strict CSP (img-src 'self' data:) before the piece's thumbnail is cached.
async function toDataUrl(url) {
  if (!url) return null;
  try {
    const r = await ooFetch(toHttp(url));
    if (!r.ok) return null;
    const ct = r.headers.get('content-type') || 'image/png';
    return `data:${ct};base64,${Buffer.from(await r.arrayBuffer()).toString('base64')}`;
  } catch { return null; }
}

// ── Per-frame curation state (hidden / animate / speed), merged over the registry defaults ──
function getState(slug) {
  const c = bySlug(slug);
  if (!c) return null;
  const st = db.getCollectionState(slug);
  return {
    hidden: st ? !!st.hidden : false,
    animate: st && st.animate != null ? !!st.animate : c.animateDefault,
    // Speed-controlled collections carry a 0..10 motion speed (0 = static); others have none.
    speed: c.speedControl ? (st && st.speed != null ? st.speed : c.speedDefault) : null,
    // Choice collections carry a selected option value (a string from the registry options); others none.
    choice: c.choice ? (st && st.choice != null ? st.choice : c.choice.default) : null,
  };
}
function setState(slug, patch) {
  if (!bySlug(slug)) throw new Error('Unknown collection.');
  db.setCollectionState(slug, patch);
  return getState(slug);
}

// Sorted by collection name (the order shown in the Settings card and the add picker; control.js
// renders in this server order). Includes piece counts for the UI.
function list() {
  return REGISTRY
    .map((c) => {
      const st = getState(c.slug);
      return {
        slug: c.slug, artist: c.artist, name: c.name, chain: c.chain,
        hidden: st.hidden, animate: st.animate,
        // A speedControl collection shows a 0..10 slider, a choice collection shows a dropdown, and an
        // animatable collection shows the on/off Animate switch — the three are mutually exclusive.
        animatable: c.animatable !== false && !c.speedControl && !c.choice,
        speedControl: !!c.speedControl, speed: st.speed, speedMax: 10,
        // A choice collection: the control descriptor (label + options) plus the current value, for the dropdown.
        choice: c.choice ? { label: c.choice.label, options: c.choice.options, value: st.choice } : null,
        fixedToken: c.fixedToken || null,    // single-piece collection: no Token-ID prompt
        crop: c.crop || null, aspect: c.aspect || null,
        pieces: db.countConnected(c.slug),
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

module.exports = { REGISTRY, COLLECTIONS_DIR, bySlug, resolveToken, mirrorBundle, removeBundle, cacheThumb, toDataUrl, getState, setState, list, isMirrored, liveRpcForPath };

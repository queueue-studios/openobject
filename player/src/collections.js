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
    // This collection animates on load via its global toggleRotation() (called directly by the animate
    // hook, not the menu below).
    animateDefault: true,
    // The bundle carries a hover/tap export menu (#menu-hover: Save PNG / Print Sheet / Toggle Rotation)
    // meant for standalone desktop use. On the display that is stray chrome — a tap (mobile) or a corner
    // hover (desktop) pops it over the art, and controls belong in the panel's Connected Collections, not
    // on the stage (§6). Hiding it (display:none) takes it out of hover and tap entirely; the programmatic
    // toggleRotation() animate path is unaffected. Only this collection ships such a menu.
    hideSelectors: ['#menu-hover'],
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
    // p5.js shows its built-in loading screen (#p5_loading, styled purple in this bundle) while it
    // preloads the 5MB sketch + 5MB photo. The display reveals a connected piece on the iframe's `load`,
    // which fires before p5 finishes that preload, so the loading text flashes during the crossfade into
    // this heavy piece. Hide it from the first paint (the same seam as Lost in Moffat County's #p5_loading
    // and The Bloom's #startOverlay): a brief blank while the photo settles replaces the stray text,
    // keeping the stage chrome-free (§6).
    hideSelectors: ['#p5_loading'],
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
    // p5.js shows its built-in loading screen (#p5_loading, an artist-styled purple "loading..." div) while
    // the sketch preloads its day/night photos. The display reveals a connected piece on the iframe's document
    // `load`, which fires before p5 finishes loading those images, so that loading screen flashes during the
    // crossfade into this image-heavy piece. Hide it from the first paint (the same hideSelectors seam as The
    // Bloom's #startOverlay): a brief blank while the photo finishes loading replaces the stray text, keeping
    // the stage chrome-free (§6).
    hideSelectors: ['#p5_loading'],
    // The photos are square (3840^2 / 2500^2) drawn object-fit: contain, so on the 1:1 stage they fill edge
    // to edge (no crop, no aspect).
    // Of the contract's live tokens, 3/4/5/6 carry an animation_url and render here; token 1 ("Desert Steel")
    // and token 7 ("Resolute") are static images with no animation_url and are intentionally NOT supported
    // (each resolves with a clear "no artwork URL" error and can be a normal upload instead). supportedTokens
    // drives the add modal's "Supported Token IDs" hint; it is display-only (the resolver still decides what
    // actually loads), so it is the one collection that lists a subset rather than a single fixedToken.
    supportedTokens: [3, 4, 5, 6],
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
    // The piece opens behind a full-screen "Click to Bloom" overlay (#startOverlay) that also gates the
    // bloom; a passive frame can't click, so the bloom hook auto-starts it on every display, silently (the
    // music never plays, §12). The overlay lives in the static HTML, so it would paint (then fade over its
    // own 0.8s) before the hook can run — a brief "Click to Bloom" flash; hideSelectors rules it out from the
    // first paint (the hook still reveals the garden). It self-animates after that (flowers sway and spin on
    // their own, a spaceship drifts), so no Animate toggle. Its hand interactions (click a flower to spin,
    // the music panel) are not supported on a passive, muted frame.
    animateDefault: false,
    animatable: false,
    animateHook: 'bloom',
    hideSelectors: ['#startOverlay'],
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
  {
    slug: 'chromie-squiggle',
    artist: 'Erick Calderon (Snowfro)',
    name: 'Chromie Squiggle',
    chain: 'Ethereum',
    contract: '0x059edd72cd353df5106d2b9cc5ab83a52287ac3a',
    rpc: 'https://ethereum-rpc.publicnode.com',
    // The OG Art Blocks piece: project 0 on the platform's shared Core contract. That one contract hosts
    // hundreds of unrelated projects, so a raw Token ID could resolve a completely different artwork; we
    // accept the whole Chromie Squiggle SERIES but pin resolution to project 0 (requireProject): any
    // Squiggle's Token ID works, a non-Squiggle id on this contract is rejected. (Unlike code-art / The
    // Bloom, which pin one piece on a grab-bag contract, the Squiggles are a real ~10k seeded series, so
    // the owner enters their own Token ID; cf. the Pendulum lesson, don't fixedToken a true series.)
    requireProject: '0',
    // Each token's generator HTML inlines that token's own hash (token id in the path, no query seed), so
    // each token mirrors its own bundle (perToken), like send/receive. But unlike send/receive the squiggle
    // reads no live on-chain state: it is fully deterministic from the inlined hash, so once p5 is localized
    // it plays entirely offline (no liveRpc).
    perToken: true,
    // The only external asset is p5.js 1.0.0 by absolute cdnjs URL; localize it into the bundle so the piece
    // renders with no network (the Golden Lining / Lost in Moffat County mechanism).
    localizeAbsolute: true,
    // Animation is a SPEED control, not on/off: the sketch starts static (loops=false) and cycles the
    // squiggle's colour each frame only while loops is true, at a rate the artist drives with the arrow
    // keys (a global `speed`, ~0.1..20). We surface that as a 0..10 motion speed (Golden Lining's slider):
    // 0 freezes it (the as-minted still), 1..10 set the colour-cycle pace. The default 1 matches the
    // official piece's own `speed` (its gentle click-to-animate pace), so it looks right out of the box. A
    // dedicated hook drives the sketch's own `loops` and `speed` (both reachable as shared top-level
    // bindings from an injected classic script). The 0 = off point covers the on/off, so there is no
    // separate Animate switch.
    speedControl: true,
    speedDefault: 1,
    speedHook: 'squiggle',
    // The metadata declares aspect_ratio 1.5 and the sketch locks its canvas to 3:2. By default the piece
    // is shown faithfully at 3:2 (Fit), letterboxed on the bare black stage on its white field, the
    // canonical Art Blocks look (the Golden Lining pattern, HANDOFF §6). This is the one connected piece
    // that also offers a per-piece Fit/Fill toggle: Fill covers the stage and centre-crops the 3:2 instead
    // of letterboxing it (Matt's call, 2026-06-20). Fit/Fill stays off for every other connected
    // collection (their bundles size themselves).
    aspect: '3 / 2',
    fitFill: true,
    // The artist draws the background from his own `backgroundArray` (20 shades, white..black), cycled by
    // spacebar. We expose just the two endpoints as a Background choice (a dropdown): White (index 0, the
    // default and canonical field) or Black (index 10). The combined squiggle hook sets `backgroundIndex`
    // from ?oochoice. No `choiceHook` here: that one hook applies both the speed and the background, which
    // makes the squiggle the first connected piece to carry more than one control (speed + background, plus
    // the Fit/Fill on its card).
    choice: {
      label: 'Background',
      default: '0',
      options: [
        { value: '0', label: 'White' },
        { value: '10', label: 'Black' },
      ],
    },
  },
  {
    slug: 'bouncing-openobject-logo',
    artist: 'OpenObject',
    name: 'Bouncing OpenObject Logo',
    chain: 'Ethereum',
    contract: '0xa6279e1bcc8dfab0fef4e556d1cf9d6eee864de7',
    rpc: 'https://ethereum-rpc.publicnode.com',
    // ERC-1155, so the metadata location is read from uri(uint256), not tokenURI (like Dune Reveries).
    erc1155: true,
    // The whole collection is this single piece (token 1); fixedToken auto-resolves it (no Token-ID
    // prompt), still read on-chain for faithfulness — the Golden Lining / The Bloom / Binary Mountains shape.
    fixedToken: '1',
    // OpenObject's own piece, and the sample seeded into every fresh Library (HANDOFF §20). The artwork is a
    // fully self-contained HTML file (an inline SVG wordmark + CSS + JS, no external assets), so the mirror is
    // a clean one-file copy. The mark bounces and recolours on its own (DVD-screensaver style), so it is
    // self-animating — nothing to engage on load, no Animate control. Its size is a % of the viewport's short
    // side, so it fills the stage edge to edge and reads the same on the 1:1 frame and a widescreen Mac alike;
    // no crop, no aspect.
    animateDefault: false,
    animatable: false,
    // The first collection to use the general multi-control `controls` model: an ordered list of slider/select
    // controls (here the piece's own Speed / Size / Corner effect), surfaced as collection settings and applied
    // at display time by BOUNCE_HOOK from ?oo_<key> params. (The older speedControl/choice flags each carry a
    // single control; `controls` generalises that to any number, which this two-slider-plus-select piece needs.)
    controls: [
      { key: 'speed',  type: 'range',  label: 'Speed',         min: 1, max: 12, step: 0.5, default: 2.5, suffix: '×' },
      { key: 'size',   type: 'range',  label: 'Size',          min: 5, max: 40, step: 1,   default: 16,  suffix: '%' },
      { key: 'corner', type: 'select', label: 'Corner effect', default: 'confetti', options: [
          { value: 'confetti',  label: 'Confetti' },
          { value: 'flash',     label: 'Flash' },
          { value: 'pulse',     label: 'Pulse' },
          { value: 'shockwave', label: 'Shockwave' },
          { value: 'none',      label: 'None' },
      ] },
    ],
    controlHook: 'bounce',
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
  // Shared platform contracts (e.g. the Art Blocks Core contract) host many unrelated projects under one
  // contract address. requireProject pins resolution to a single project (Chromie Squiggle = Art Blocks
  // project 0) so a Token ID from a different project on the same contract is rejected here rather than
  // mirrored under the wrong collection. Art Blocks metadata carries project_id; collections without it
  // (Tezos, single-project contracts) leave requireProject unset and are unaffected.
  if (c.requireProject != null && String(meta.project_id) !== String(c.requireProject)) {
    throw new Error(`That Token ID isn't a ${c.name}. Enter a ${c.name}'s Token ID.`);
  }
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

// Injected into Erick Calderon's "Chromie Squiggle" (Art Blocks project 0). The sketch exposes three
// globals we curate, all top-level `let` bindings that a classic script injected into the same document
// can set directly: `loops` (colour cycle on/off, the artist's click), `speed` (cycle rate, the artist's
// arrow keys), and `backgroundIndex` (which entry of his white..black `backgroundArray` to paint, the
// artist's spacebar). This one combined hook applies both of the squiggle's controls at display time:
//   • ?oospeed=N (0..10 motion speed): 0 freezes the piece (loops off, the as-minted still), 1..10 turn the
//     colour loop on and set its pace, mapped straight onto the artist's own `speed` (default 1 = original).
//   • ?oochoice=N (Background): set `backgroundIndex` to the chosen entry (0 = White, 10 = Black).
// Applied once setup() has created the canvas (so the bindings are initialised, no temporal-dead-zone); a
// param left out leaves that global untouched.
const SQUIGGLE_HOOK = `
<script>
(function(){
  var qs = new URLSearchParams(location.search);
  var sp = parseFloat(qs.get('oospeed'));
  var bg = parseInt(qs.get('oochoice'), 10);
  var n = 0;
  var iv = setInterval(function(){
    if (++n > 300) { clearInterval(iv); return; }   // ~30s safety
    if (!document.querySelector('canvas')) return;  // setup() ran → globals are initialised
    clearInterval(iv);
    try {
      if (!isNaN(sp)) { sp = Math.max(0, Math.min(10, sp)); if (sp <= 0) { loops = false; } else { loops = true; speed = sp; } }
      if (!isNaN(bg)) { backgroundIndex = bg; }
    } catch (e) {}
  }, 100);
})();
</script>`;

// Injected into OpenObject's own "Bouncing OpenObject Logo": the piece exposes three top-level `let`
// bindings — `speed` (1..12), `sizePct` (5..40, % of the viewport's short side) and `cornerMode` (the
// corner-hit effect) — which a classic <script> injected into the same document can set directly (the
// Chromie Squiggle pattern: classic scripts share the top-level lexical scope). It self-animates (bounces
// and recolours on its own), so this is not an Animate toggle: it just applies the owner's chosen Speed /
// Size / Corner effect from the display params (?oo_speed / ?oo_size / ?oo_corner). The loop re-reads
// `speed` and `sizePct` every frame and `cornerMode` on each corner hit, so setting them once is enough; a
// param left out leaves that global at the artist's default. We wait out any temporal-dead-zone (the
// bindings are created when the artist's script runs) before assigning.
const BOUNCE_HOOK = `
<script>
(function(){
  var qs = new URLSearchParams(location.search);
  var sp = parseFloat(qs.get('oo_speed'));
  var sz = parseFloat(qs.get('oo_size'));
  var cm = qs.get('oo_corner');
  var n = 0;
  var iv = setInterval(function(){
    if (++n > 300) { clearInterval(iv); return; }   // ~30s safety
    try { void speed; void sizePct; void cornerMode; } catch (e) { return; } // bindings not ready yet (TDZ)
    clearInterval(iv);
    try {
      if (!isNaN(sp)) speed = Math.max(1, Math.min(12, sp));
      if (!isNaN(sz)) sizePct = Math.max(5, Math.min(40, sz));
      if (cm) cornerMode = cm;
    } catch (e) {}
  }, 50);
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

// Mirror a piece's bundle. An add ALWAYS re-mirrors (no skip-if-already-present shortcut), so a render
// fix to the mirror step (the hooks, the hideSelectors overlay-hide, dropScripts) reaches an existing
// bundle just by removing and re-adding the piece, instead of silently reusing a stale copy. mirrorInto
// overwrites in place and writes index.html last, so a live shared-collection sibling never sees a
// missing bundle, and mirrorBundle is only ever called from the add flow (never on boot), so the
// re-fetch is bounded to an explicit add.
async function mirrorBundle(slug, sourceUrl, tokenId) {
  const c = bySlug(slug);
  const out = outDir(slug, tokenId);                                         // per-token dir, or the shared bundle
  const existed = fs.existsSync(path.join(out, 'index.html'));              // re-adding over an existing bundle?
  try {
    await mirrorInto(c, out, sourceUrl);
  } catch (e) {
    // A fetch timed out or the source died mid-mirror. Only drop a brand-new dir, so its retry starts
    // clean; an existing bundle is left intact (its old copy still plays), so a failed re-mirror can
    // never destroy a working piece (index.html is written last, so a kept dir still has a valid one).
    if (!existed) fs.rmSync(out, { recursive: true, force: true });
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

  // Hide any of the artist's static interaction chrome that is meaningless on a passive frame, from the
  // very first paint. The Bloom ships a full-screen "Click to Bloom" gate (#startOverlay): the bloom hook
  // dismisses it, but because it lives in the served HTML it would paint (then fade over its own 0.8s)
  // before the hook can run — a brief flash; a head-level rule hides the selector before it ever paints,
  // while the hook still fires startExperience() to reveal the garden. (SNOW_HOOK hides Binary Mountains'
  // chrome similarly but via JS, since those nodes are created after load; a node already in the served
  // HTML needs the rule in <head> to beat the first paint.)
  if (c && Array.isArray(c.hideSelectors) && c.hideSelectors.length) {
    const css = `<style>${c.hideSelectors.join(',')}{display:none!important}</style>`;
    html = html.includes('</head>') ? html.replace('</head>', css + '\n</head>') : css + html;
  }

  // Inject the matching hook (engaged by ?oochoice / ?ooanim / ?oospeed at display time): a choice
  // collection gets its own control hook (snow → set the level + hide overlays); a bloom/easterEgg
  // collection fires the artist's own handler once (start the bloom / toggle the easter egg); a
  // speedControl collection gets a cosine sweep (Golden Lining) or, for the squiggle, the combined squiggle
  // hook (which drives its loops/speed AND its background from the display params); other Animate-control
  // pieces get the generic fire-once hook. Self-animating / still pieces (Kittoe, send/receive) get none.
  const hook = c && c.controlHook === 'bounce' ? BOUNCE_HOOK
    : c && c.choiceHook === 'snow' ? SNOW_HOOK
    : c && c.animateHook === 'bloom' ? BLOOM_HOOK
    : c && c.animateHook === 'easterEgg' ? EASTER_HOOK
    : c && c.speedControl ? (c.speedHook === 'squiggle' ? SQUIGGLE_HOOK : SPEED_HOOK)
    : (c && c.animatable !== false ? ANIMATE_HOOK : '');
  if (hook) html = html.includes('</body>') ? html.replace('</body>', hook + '\n</body>') : html + hook;
  fs.mkdirSync(out, { recursive: true });
  fs.writeFileSync(path.join(out, 'index.html'), html, 'utf8');
}

// Reclaim a deleted piece's mirrored bundle. A perToken collection gives each token its own dir,
// removed here. A shared bundle serves every token of its collection (the per-piece seed rides in the
// URL query), so it is kept until the LAST piece is gone: once no library rows reference the
// collection, drop the whole dir (the shared bundle, any perToken leftovers, and the thumbs). The
// delete route removes the row before calling this, so countConnected reflects what remains.
function removeBundle(slug, tokenId) {
  const c = bySlug(slug);
  if (!c) return;
  if (c.perToken) fs.rm(path.join(bundleDir(slug), String(tokenId)), { recursive: true, force: true }, () => {});
  if (db.countConnected(slug) === 0) fs.rm(bundleDir(slug), { recursive: true, force: true }, () => {});
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

// A collection's display controls (the general multi-control model): an ordered list of range/select
// descriptors the owner sets per collection, applied at display time by the collection's controlHook from
// ?oo_<key> params. (The older speedControl/choice flags are the original single-control shorthands.)
function controlsOf(c) { return Array.isArray(c && c.controls) ? c.controls : []; }

// Merge a collection's stored control values over the registry defaults, validating each: a range is coerced
// to a number and clamped to [min,max]; a select must be one of its option values. `stored` may be the JSON
// string from the DB or an already-parsed object; an unknown / blank value falls back to the control default.
function mergedControls(c, stored) {
  let s = {};
  if (typeof stored === 'string') { try { s = JSON.parse(stored) || {}; } catch { s = {}; } }
  else if (stored && typeof stored === 'object') s = stored;
  const out = {};
  for (const ctl of controlsOf(c)) {
    let v = s[ctl.key];
    if (ctl.type === 'range') {
      v = Number(v);
      if (!Number.isFinite(v)) v = ctl.default;
      v = Math.max(ctl.min, Math.min(ctl.max, v));
    } else if (ctl.type === 'select') {
      v = (ctl.options || []).some((o) => String(o.value) === String(v)) ? String(v) : ctl.default;
    } else {
      v = v == null ? ctl.default : v;
    }
    out[ctl.key] = v;
  }
  return out;
}

// ── Per-frame curation state (hidden / animate / speed / controls), merged over the registry defaults ──
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
    // A controls collection carries a {key:value} of its display controls, each merged over the registry
    // default and validated; collections without the general controls model carry none.
    controls: controlsOf(c).length ? mergedControls(c, st && st.controls) : null,
  };
}
function setState(slug, patch) {
  const c = bySlug(slug);
  if (!c) throw new Error('Unknown collection.');
  const dbPatch = { ...patch };
  // A controls patch arrives as a partial {key:value}; merge it over the current values, validate the whole
  // set (mergedControls clamps ranges / checks selects), and store it as the JSON the DB column holds.
  if (patch.controls !== undefined) {
    const cur = mergedControls(c, (db.getCollectionState(slug) || {}).controls);
    dbPatch.controls = JSON.stringify(mergedControls(c, { ...cur, ...(patch.controls || {}) }));
  }
  db.setCollectionState(slug, dbPatch);
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
        // A speedControl collection shows a 0..10 slider, a choice collection shows a dropdown, an animatable
        // collection shows the on/off Animate switch, and a controls collection shows its own list of
        // sliders/selects — mutually exclusive surfaces (a collection uses one of these models).
        animatable: c.animatable !== false && !c.speedControl && !c.choice && !(c.controls && c.controls.length),
        speedControl: !!c.speedControl, speed: st.speed, speedMax: 10,
        // A choice collection: the control descriptor (label + options) plus the current value, for the dropdown.
        choice: c.choice ? { label: c.choice.label, options: c.choice.options, value: st.choice } : null,
        // A controls collection: each control descriptor with its current value, for the Settings card.
        controls: st.controls ? c.controls.map((ctl) => ({ ...ctl, value: st.controls[ctl.key] })) : null,
        fixedToken: c.fixedToken || null,    // single-piece collection: no Token-ID prompt
        // IDs for the add modal's "Supported Token IDs" hint: a fixedToken collection's one id, an explicit
        // supportedTokens subset (e.g. Lost in Moffat County's 3,4,5,6), or null for open collections (no hint).
        supportedTokens: c.supportedTokens ? c.supportedTokens.map(String) : (c.fixedToken ? [String(c.fixedToken)] : null),
        crop: c.crop || null, aspect: c.aspect || null,
        // Whether this connected collection offers a per-piece Fit/Fill toggle (off for all but the
        // squiggle); control.js shows the Fit/Fill button on its Library card only when set.
        fitFill: !!c.fitFill,
        pieces: db.countConnected(c.slug),
      };
    })
    .sort((a, b) => a.name.localeCompare(b.name));
}

module.exports = { REGISTRY, COLLECTIONS_DIR, bySlug, resolveToken, mirrorBundle, removeBundle, cacheThumb, toDataUrl, getState, setState, list, isMirrored, liveRpcForPath };

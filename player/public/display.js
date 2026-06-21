'use strict';

// OpenObject display — rotation engine.
//
// Renders the Rotation (v1 = the whole Library, in upload order) edge-to-edge on the
// black stage: Fit/Fill per clip, one global equal-time duration for every piece, and
// video/animation loops to fill it (a video longer than the duration is cut off when
// the timer advances). Order: Sequence / Shuffle (HANDOFF §7). New uploads,
// deletions, Fit/Fill flips, and duration/order changes fold in live without restarting
// the loop (polled). Always muted (§12).

const idle = document.getElementById('idle');
const layers = [document.getElementById('layer0'), document.getElementById('layer1')];

// The idle hint shows the address to reach the control panel: the host this page was opened at
// (localhost:3000 when the Mac is the display). The frame's kiosk opens localhost though, where the
// owner reaches it at the advertised name instead, so on a loopback host fall back to the server's
// mDNS name (openobject.local on the frame; none on a Mac/standalone, where the host already reads
// right). See §6.
const hintHost = document.querySelector('.hint .host');
if (hintHost) {
  hintHost.textContent = location.host;
  if (location.hostname === 'localhost' || location.hostname.startsWith('127.')) {
    fetch('/api/system').then((r) => r.json()).then((s) => { if (s && s.mdns) hintHost.textContent = s.mdns; }).catch(() => {});
  }
}

let items = [];
let durationMs = 8000;
let mode = 'sequence';

let pos = -1; // index in `items` of the piece on screen
let currentId = null; // its library id — survives reordering as the library changes
let currentSig = null; // fit+filename of the on-screen piece — detects a live restyle
let front = 0; // which layer is currently visible
let timer = null;
let started = false;
let shuffleQueue = [];
let sleeping = false; // Sleep Hours / manual Blank: showing the dimmed mark (HANDOFF §13)
let shiftTimer = null; // slow pixel-shift while asleep (anti-burn-in)

const sig = (item) => item.kind === 'connected'
  ? 'c|' + item.collection + '|' + item.source_url + '|' + (item.animate ? 1 : 0) + '|' + (item.speed == null ? '' : item.speed) + '|' + (item.rpcUrl || '') + '|' + item.fit
  : item.fit + '|' + item.filename;
const once = (fn) => {
  let done = false;
  return () => { if (!done) { done = true; fn(); } };
};
const shuffle = (a) => {
  for (let i = a.length - 1; i > 0; i--) {
    const j = (Math.random() * (i + 1)) | 0;
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

function pickNext() {
  const n = items.length;
  if (n <= 1) return 0;
  if (mode === 'shuffle') {
    if (shuffleQueue.length === 0) {
      shuffleQueue = shuffle(items.map((_, i) => i));
      if (shuffleQueue[0] === pos && shuffleQueue.length > 1) shuffleQueue.push(shuffleQueue.shift());
    }
    return shuffleQueue.shift();
  }
  return (pos + 1) % n; // sequence
}

function render(layer, item, onReady) {
  layer.className = 'layer fit-' + (item.fit === 'fill' ? 'fill' : 'fit');
  let el;
  if (item.kind === 'connected') {
    // Connected artwork: our same-origin mirror of the collection bundle. A shared-bundle collection
    // carries its per-piece seed in the official URL's query string; a perToken collection (Art
    // Blocks-style) has its own bundle dir per token. We also append rpc_url for live collections (so
    // the piece reads on-chain state from our node) and ooanim for collections with an animate hook.
    el = document.createElement('iframe');
    el.setAttribute('scrolling', 'no');
    el.setAttribute('sandbox', 'allow-scripts allow-same-origin'); // runs scripts; can't navigate/popup
    el.addEventListener('load', onReady, { once: true });
    const params = [];
    const qIdx = item.source_url ? item.source_url.indexOf('?') : -1;
    if (qIdx >= 0) params.push(item.source_url.slice(qIdx + 1));         // per-piece seed (shared bundles)
    if (item.rpcUrl) params.push('rpc_url=' + encodeURIComponent(item.rpcUrl)); // live RPC override
    if (item.animate) params.push('ooanim=1');                          // fire the bundle's animate hook
    if (item.speed != null) params.push('oospeed=' + encodeURIComponent(item.speed)); // 0..10 cosine sweep speed
    if (item.choice != null) params.push('oochoice=' + encodeURIComponent(item.choice)); // single-choice control value
    const tokenSeg = item.perToken && item.token_id != null ? '/' + encodeURIComponent(item.token_id) : '';
    el.src = '/collections/' + item.collection + tokenSeg + '/index.html' + (params.length ? '?' + params.join('&') : '');
    // Some collections compose the art in a centered inset with a black margin (e.g. send/receive's
    // sprite card fills the middle 60%). `crop` zooms the iframe so the art reaches the panel edges
    // (HANDOFF §6). Oversizing the iframe (not CSS-scaling) keeps the generator rendering at full
    // resolution, so pixel art stays crisp; the layer clips the overflow (display.css .layer.crop).
    if (item.crop && item.crop > 0 && item.crop < 1) {
      layer.classList.add('crop');
      el.style.setProperty('--crop-scale', (100 / item.crop).toFixed(3) + '%');
    }
    // A connected piece that declares an aspect (e.g. a landscape photo, not a square-composed
    // sketch) is sized to that aspect and centered, so the bare black stage forms the letterbox
    // top/bottom — the iframe equivalent of object-fit: contain (HANDOFF §6). No painted background.
    if (item.aspect) {
      layer.classList.add('aspect');
      el.style.setProperty('--ar', item.aspect);
    }
  } else if (item.kind === 'video') {
    el = document.createElement('video');
    el.muted = true;          // silent art on a wall (§12)
    el.loop = true;           // loop to fill the duration
    el.playsInline = true;
    el.autoplay = true;
    el.addEventListener('loadeddata', onReady, { once: true });
    el.src = '/uploads/' + item.filename;
    el.play().catch(() => {});
  } else {
    el = document.createElement('img'); // stills + animated (GIF/WebP/AVIF) + SVG (SMIL) hold/loop
    el.addEventListener('load', onReady, { once: true });
    el.addEventListener('error', onReady, { once: true });
    el.src = '/uploads/' + item.filename;
  }
  layer.replaceChildren(el);
  // Safety net so the loop can't wedge if the readiness event never fires. Stills and video settle
  // in well under 500ms, so a short fallback is fine. A connected piece is different: it becomes
  // ready only when its synchronous generate() finishes (which is also when the iframe 'load' event
  // fires, measured), and that can take several seconds, varying by seed and CPU. A 500ms fallback
  // would win the race on a slow frame and start the duration clock mid-generate, so connected waits
  // for its 'load' event with only a long backstop here (HANDOFF §7).
  setTimeout(onReady, item.kind === 'connected' ? 30000 : 500);
}

// Render + crossfade to a specific piece.
function show(item) {
  pos = items.indexOf(item);
  currentId = item.id;
  currentSig = sig(item);
  const back = 1 - front;
  const reveal = once(() => {
    layers[back].classList.add('show');
    layers[front].classList.remove('show');
    front = back;
    // Hide the idle mark as the piece crossfades in, not before: a slow connected generate then
    // keeps the mark on screen instead of leaving a black gap until the art is ready.
    idle.classList.add('hidden');
    // Start the piece's duration clock when it actually becomes visible, not when advance() kicked
    // off the render. A connected piece's iframe runs a heavy synchronous generate() that blocks the
    // shared main thread (it is same-origin), so its reveal can land seconds after advance(): long
    // enough that, timed from advance(), the piece is on screen for only (duration minus generate
    // time). Arming the next advance here gives every piece its full visible duration (HANDOFF §7).
    armAdvance();
  });
  render(layers[back], item, reveal);
  started = true;
}

// (Re)arm the timer that advances to the next piece, one global duration from now. A lone piece
// holds forever (no timer). Called from a piece's reveal so the duration counts visible time.
function armAdvance() {
  clearTimeout(timer);
  timer = items.length > 1 ? setTimeout(advance, durationMs) : null;
}

function advance() {
  clearTimeout(timer);
  timer = null;
  if (items.length === 0) return showIdle();
  pos = pickNext();
  const item = items[pos];
  // show() re-arms the next advance from its reveal (so a slow connected piece still gets its full
  // time). When the pick is the same lone piece, we keep showing it: no reload, no new timer.
  if (item.id !== currentId) show(item);
}

function showIdle() {
  clearTimeout(timer);
  timer = null;
  started = false;
  pos = -1;
  currentId = null;
  currentSig = null;
  shuffleQueue = [];
  layers.forEach((l) => { l.classList.remove('show'); l.replaceChildren(); });
  idle.classList.remove('hidden');
}

// Sleep Hours / manual Blank (HANDOFF §13): stop playback and show the boot/idle mark,
// dimmed and text-free, drifting a few pixels on a slow cycle so it can't sit on the panel.
function enterSleep() {
  if (sleeping) return;
  sleeping = true;
  showIdle();                    // tear down playback + show the mark
  idle.classList.add('asleep');  // dim it and hide the caption (display.css)
  startPixelShift();
}
function exitSleep() {
  sleeping = false;
  stopPixelShift();
  idle.classList.remove('asleep'); // playback resumes via the normal flow below
}
function startPixelShift() {
  stopPixelShift();
  const drift = () => {
    const x = Math.round((Math.random() * 2 - 1) * 6);
    const y = Math.round((Math.random() * 2 - 1) * 6);
    idle.style.transform = `translate(${x}px, ${y}px)`;
  };
  drift();
  shiftTimer = setInterval(drift, 90000); // a few px every 90s, gliding via the CSS transition
}
function stopPixelShift() {
  if (shiftTimer) { clearInterval(shiftTimer); shiftTimer = null; }
  idle.style.transform = '';
}

function apply(state) {
  durationMs = state.durationMs;
  mode = state.mode;

  if (state.asleep) return enterSleep();  // Sleep Hours / manual Blank (HANDOFF §13)
  if (sleeping) exitSleep();              // just woke — fall through and resume the rotation

  // A pinned piece collapses the rotation to just itself — held permanently (HANDOFF §7).
  const pinned = state.pinnedId != null ? state.items.find((i) => i.id === state.pinnedId) : null;
  items = pinned ? [pinned] : state.items;
  shuffleQueue = [];

  if (items.length === 0) return showIdle();

  if (currentId != null) pos = items.findIndex((i) => i.id === currentId);
  if (!started || pos < 0) return advance();             // (re)start, or skip a deleted current
  if (sig(items[pos]) !== currentSig) show(items[pos]);  // current piece restyled (Fit/Fill) → re-render
  if (items.length > 1 && timer === null) armAdvance(); // 1→many: resume cadence (a lone piece had none)
}

async function tick() {
  try {
    apply(await fetch('/api/display').then((r) => r.json()));
  } catch {
    /* offline or restarting — keep showing what's up; playback is local (§9) */
  }
}

tick();
setInterval(tick, 5000); // fold in library/settings changes without restarting the loop

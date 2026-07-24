'use strict';

// OpenObject display — rotation engine.
//
// Renders the Rotation (v1 = the whole Library, in upload order) edge-to-edge on the
// black stage: Fit/Fill per clip, one global equal-time duration for every piece, and
// video/animation loops to fill it (a video longer than the duration is cut off when
// the timer advances). Order: Sequence / Shuffle (HANDOFF §7). New uploads,
// deletions, Fit/Fill flips, and duration/order changes fold in live without restarting
// the loop (polled). Uploaded video honors the display's Sound setting, falling back to
// muted only where a plain browser refuses unmuted autoplay (§12).
//
// DISPLAY-TARGET CONTRACT (the Display role — HANDOFF §20, 2026-07-01; MAC-APP-PLAN §A4).
// This page renders exactly one Host, and that Host is WHICHEVER ONE SERVED THIS PAGE. Every data
// read (/api/display, /api/system) and every asset (/display.css, /arcade.js, /assets/…, the
// same-origin connected-bundle mirror) is a ROOT-RELATIVE, same-origin URL, so "which Host this
// Display shows" is decided entirely by the URL the page is opened at — nothing here assumes
// localhost. The frame's kiosk opens http://localhost/display and every fetch resolves to the
// frame itself (unchanged, exactly as before). The Mac app just opens Chrome at the CHOSEN Host's
// /display (its own localhost when hosting, or a discovered Host's LAN address) and the same
// relative fetches resolve to that Host. Deliberate NON-GOAL: no cross-origin "?host=" targeting
// (a Display served by Host A rendering Host B) — that would force CORS + a per-Host CSP relaxation
// and risk the frame's zero-config kiosk, for no gain when pointing Chrome at the right URL already
// does it. Keep every URL in this file relative; do not hardcode an origin.

const idle = document.getElementById('idle');
const layers = [document.getElementById('layer0'), document.getElementById('layer1')];
const arcadeCanvas = document.getElementById('arcade'); // hidden self-playing demo (easter egg)

// The idle hint shows an address the owner can use to reach the control panel and add art. The
// kiosk opens the display at localhost, but localhost is reachable only ON this machine, so when the
// page is on a loopback host we ask the server for a better address. Preference order: (1) the mDNS
// name (openobject.local on the frame); (2) a LAN address (so it is reachable from a phone or another
// computer, the useful case on a Mac, where there is no mDNS name); otherwise (3) leave whatever host
// the page was opened at. See §6.
const hintHost = document.querySelector('.hint .host');
if (hintHost) {
  hintHost.textContent = location.host;
  if (location.hostname === 'localhost' || location.hostname.startsWith('127.')) {
    fetch('/api/system').then((r) => r.json()).then((s) => {
      if (!s) return;
      if (s.mdns) { hintHost.textContent = s.mdns; return; }
      const lan = s.addresses && s.addresses[0];
      if (lan) hintHost.textContent = lan + (location.port ? ':' + location.port : '');
    }).catch(() => {});
  }
}

let items = [];
let durationMs = 8000;
let mode = 'sequence';
let muted = true; // the web display's Sound setting (§12): true = video muted. Set from /api/display each poll.

let pos = -1; // index in `items` of the piece on screen
let currentId = null; // its library id — survives reordering as the library changes
let currentSig = null; // fit+filename of the on-screen piece — detects a live restyle
let front = 0; // which layer is currently visible
let timer = null;
let started = false;
let lastShowAt = 0; // when the last crossfade began — guards the hidden-layer cleanup against a live fade
let pendingLayer = -1; // layer holding a render that has not revealed yet — never free it (see freeHiddenLayer)
let shuffleQueue = [];
let itemsListSig = ''; // ids of the current items in order; the shuffle bag resets only when this changes
let sleeping = false; // Sleep Hours / manual Blank: showing the dimmed mark (HANDOFF §13)
let shiftTimer = null; // slow pixel-shift while asleep (anti-burn-in)
let arcadeOn = false; // Retro Arcade demo is taking the stage (easter egg)

// Master gate (Direction D, §12): the display's Sound setting sits ABOVE a connected piece's own
// audio. While the display is muted, a collection's audio control (today only The Bloom's `music`) is
// forced to its silent value, so Sound Off silences the whole screen — uploaded video AND connected
// audio — not just video. It reuses the existing ?oo_<control> plumbing (the bundle already honors
// oo_music=off, so a piece falls back to its own ambient/silent render), which means no bundle change
// and it works with pieces mirrored before this shipped. Used by BOTH render() (the iframe src) and
// sig() (so a live Sound flip re-renders the piece — the same crossfade-reload an Animate/Fit change
// triggers, since the value lives in the iframe URL). AUDIO_CONTROLS is the seam if audio controls
// ever grow past one; a piece with none, or already silent, is returned unchanged (no needless reload).
const AUDIO_CONTROLS = { music: 'off' }; // control key -> the value that means "silent"
function gatedControls(item) {
  if (!muted || !item.controls) return item.controls;
  let out = null;
  for (const k in AUDIO_CONTROLS) {
    if (k in item.controls && item.controls[k] !== AUDIO_CONTROLS[k]) {
      out = out || { ...item.controls };
      out[k] = AUDIO_CONTROLS[k];
    }
  }
  return out || item.controls;
}

const sig = (item) => item.kind === 'connected'
  ? 'c|' + item.collection + '|' + item.source_url + '|' + (item.animate ? 1 : 0) + '|' + (item.speed == null ? '' : item.speed) + '|' + (item.rpcUrl || '') + '|' + item.fit + '|' + (item.controls ? JSON.stringify(gatedControls(item)) : '')
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
    const ctl = gatedControls(item); // general controls → ?oo_<key>=value; the display's Sound gate forces audio controls silent when muted (§12)
    if (ctl) for (const k in ctl) params.push('oo_' + k + '=' + encodeURIComponent(ctl[k]));
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
    el.muted = muted;         // the display's Sound setting (§12); may fall back to muted below
    el.loop = true;           // loop to fill the duration
    el.playsInline = true;
    el.autoplay = true;
    el.addEventListener('loadeddata', onReady, { once: true });
    el.src = item.src || ('/uploads/' + item.filename);
    // Chrome refuses UNMUTED autoplay unless it was launched with --autoplay-policy=no-user-gesture-
    // required (our kiosk and the Mac app both pass it; a plain browser opened at /display does not).
    // Without the flag an unmuted play() rejects and nothing plays at all, so catch that and retry
    // muted: art never stops, and at worst it is silent on that one un-flagged path (§12).
    el.play().catch(() => { if (!el.muted) { el.muted = true; el.play().catch(() => {}); } });
  } else {
    el = document.createElement('img'); // stills + animated (GIF/WebP/AVIF) + SVG (SMIL) hold/loop
    el.addEventListener('load', onReady, { once: true });
    el.addEventListener('error', onReady, { once: true });
    el.src = item.src || ('/uploads/' + item.filename);
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

// Free the off-screen layer once a crossfade has settled, so a previously-shown piece's iframe stops
// rendering behind the visible one (an opacity:0 iframe keeps animating and competes for the GPU on a
// weak panel). The timestamp guard never clears while a fade may be running (that would cut off the
// outgoing piece). The next show() repopulates the layer from scratch, exactly as it already did, so
// nothing visible changes — only the wasted background rendering stops.
function freeHiddenLayer() {
  if (Date.now() - lastShowAt < 700) return;     // a crossfade may still be running — leave both layers
  const idx = 1 - front;
  // A render in flight lives in the back layer and has not flipped `front` yet, so it looks exactly like
  // a stale layer to the two checks below: `front` still points at the OUTGOING piece, and the incoming
  // layer has no `.show` until its reveal. Freeing it would delete the piece we are waiting on, and its
  // load event would then never fire, so the reveal backstop would fade in an empty layer (a black stage
  // until something else re-renders). Only ever free a layer whose piece has actually appeared.
  if (idx === pendingLayer) return;
  const hidden = layers[idx];
  if (!hidden.classList.contains('show')) hidden.replaceChildren();
}

// Render + crossfade to a specific piece.
function show(item) {
  pos = items.indexOf(item);
  currentId = item.id;
  currentSig = sig(item);
  const back = 1 - front;
  pendingLayer = back;                  // in flight until reveal: off limits to freeHiddenLayer
  const reveal = once(() => {
    pendingLayer = -1;                  // it is on screen now, so the usual cleanup rules apply again
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
    // Once the crossfade settles, drop the layer we just faded away from so the previous piece's iframe
    // stops rendering behind the visible one (after the fade, never during it — see freeHiddenLayer).
    lastShowAt = Date.now();
    setTimeout(freeHiddenLayer, 750);
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

// Retro Arcade (the hidden easter egg): the secret key sequence on the control panel flips a
// runtime-only server flag; the display swaps the rotation for arcade.js's self-playing demo and
// holds it until Return to Art. Entering tears down playback (like Sleep) and hides the idle mark so
// the canvas owns the stage; exiting stops the loop and the rotation restarts via apply() below.
function enterArcade() {
  if (arcadeOn) return;
  arcadeOn = true;
  if (sleeping) exitSleep();
  showIdle();                    // stop video/iframe playback + reset rotation state
  idle.classList.add('hidden');  // hide the idle mark — the demo canvas covers the stage
  arcadeCanvas.hidden = false;
  if (window.RetroArcade) RetroArcade.start(arcadeCanvas);
}
function exitArcade() {
  arcadeOn = false;
  if (window.RetroArcade) RetroArcade.stop();
  arcadeCanvas.hidden = true;    // playback resumes via the rest of apply() (started=false → advance)
}

// Fold a live Sound On/Off change into the VIDEO already on screen, in place. A video's mute is not
// part of its sig, so apply() won't re-render it — this is what makes a Sound flip reach a pinned
// video, which never advances to pick up the new setting on its own. A connected piece takes the other
// path: its audio gate lives in its sig (gatedControls), so a Sound flip re-renders it instead (§12).
function syncMute() {
  const el = layers[front].firstElementChild;
  if (el && el.tagName === 'VIDEO' && el.muted !== muted) el.muted = muted;
}

function apply(state) {
  durationMs = state.durationMs;
  mode = state.mode;
  muted = !!state.muted; // web display Sound: Off mutes uploaded video (§12)

  if (state.retroArcade) return enterArcade(); // hidden self-playing demo (easter egg) owns the stage
  if (arcadeOn) exitArcade();                  // just left the demo — fall through and resume the rotation

  if (state.asleep) return enterSleep();  // Sleep Hours / manual Blank (HANDOFF §13)
  if (sleeping) exitSleep();              // just woke — fall through and resume the rotation

  // A pinned piece collapses the rotation to just itself — held permanently (HANDOFF §7).
  const pinned = state.pinnedId != null ? state.items.find((i) => i.id === state.pinnedId) : null;
  items = pinned ? [pinned] : state.items;
  // Reset the shuffle bag ONLY when the item set/order actually changes (pin, rotation edit, folder
  // switch, folder files added/removed). Wiping it on every unchanged ~5s poll restarted the pass
  // before it finished, degrading Shuffle to independent random with early repeats (§7).
  const nextSig = items.map((i) => i.id).join('|');
  if (nextSig !== itemsListSig) { shuffleQueue = []; itemsListSig = nextSig; }

  if (items.length === 0) return showIdle();

  syncMute(); // fold a live Sound On/Off change into the piece already on screen (e.g. a pinned video)

  if (currentId != null) pos = items.findIndex((i) => i.id === currentId);
  if (!started || pos < 0) return advance();             // (re)start, or skip a deleted current
  if (sig(items[pos]) !== currentSig) show(items[pos]);  // current piece restyled (Fit/Fill) → re-render
  if (items.length > 1 && timer === null) armAdvance(); // 1→many: resume cadence (a lone piece had none)
  if (items.length === 1) freeHiddenLayer(); // lone/pinned: drop any leftover iframe still rendering behind it
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

'use strict';

// OpenObject control panel — upload, Library, Rotation curation, rotation settings.
// Three tabs: Library (everything uploaded), Rotation (the curated, ordered subset on the
// panel), and Settings (sleep schedule + software self-update). Restart/shutdown stubs land next.

const grid = document.getElementById('grid');
const libCount = document.getElementById('libCount');
const emptyEl = document.getElementById('empty');
const statusEl = document.getElementById('status');
const drop = document.getElementById('drop');
const fileInput = document.getElementById('file');

const durationEl = document.getElementById('duration');
const durDown = document.getElementById('durDown');
const durUp = document.getElementById('durUp');
const unitSeg = document.getElementById('unitSeg');
const modeSeg = document.getElementById('modeSeg');

const tabLibrary = document.getElementById('tabLibrary');
const tabRotation = document.getElementById('tabRotation');
const tabSettings = document.getElementById('tabSettings');
const panelLibrary = document.getElementById('panelLibrary');
const panelRotation = document.getElementById('panelRotation');
const panelSettings = document.getElementById('panelSettings');
const rotList = document.getElementById('rotList');
const rotCount = document.getElementById('rotCount');
const rotEmpty = document.getElementById('rotEmpty');
const rotHint = document.getElementById('rotHint');

const blankBtn = document.getElementById('blankBtn');
const returnArtBtn = document.getElementById('returnArtBtn'); // shown only while the hidden demo runs
const sleepRangesEl = document.getElementById('sleepRanges');
const sleepStatus = document.getElementById('sleepStatus');
const sleepAddBtn = document.getElementById('sleepAdd');
const sleepEmptyEl = document.getElementById('sleepEmpty');
const sleepStripEl = document.getElementById('sleepStrip');

const updVersion = document.getElementById('updVersion');
const checkUpdateBtn = document.getElementById('checkUpdateBtn');
const applyUpdateBtn = document.getElementById('applyUpdateBtn');
const updApply = document.getElementById('updApply');
const dismissUpdateBtn = document.getElementById('dismissUpdateBtn');
const updStatus = document.getElementById('updStatus');

const restartBtn = document.getElementById('restartBtn');
const shutdownBtn = document.getElementById('shutdownBtn');
const rebootBtn = document.getElementById('rebootBtn');
const powerStatus = document.getElementById('powerStatus');
const reachEl = document.getElementById('reach');
const frameAddr = document.getElementById('frameAddr');
const frameMdns = document.getElementById('frameMdns');

const loginOverlay = document.getElementById('loginOverlay');
const loginForm = document.getElementById('loginForm');
const authPw = document.getElementById('authPw');
const authMsg = document.getElementById('authMsg');
const authCard = document.getElementById('authCard');

// Connected artwork: entry button, add modal, and the Settings collections card.
const addConnectedBtn = document.getElementById('addConnected');
const cxOverlay = document.getElementById('cxOverlay');
const cxClose = document.getElementById('cxClose');
const cxCollections = document.getElementById('cxCollections');
const cxToken = document.getElementById('cxToken');
const cxTokenLabel = document.getElementById('cxTokenLabel');
const cxSupported = document.getElementById('cxSupported');
const cxResult = document.getElementById('cxResult');
const cxMsg = document.getElementById('cxMsg');
const cxAdd = document.getElementById('cxAdd');
const connectedList = document.getElementById('connectedList');
const ccUnhideAll = document.getElementById('ccUnhideAll');
const ccCount = document.getElementById('ccCount');

const UNIT_MS = { seconds: 1000, minutes: 60000, hours: 3600000 };

// Inline icons (no webfont dependency — the frame runs offline).
const GRIP = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true"><circle cx="5" cy="4" r="1.3"/><circle cx="11" cy="4" r="1.3"/><circle cx="5" cy="8" r="1.3"/><circle cx="11" cy="8" r="1.3"/><circle cx="5" cy="12" r="1.3"/><circle cx="11" cy="12" r="1.3"/></svg>';
const CHEV_UP = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 15l6-6 6 6"/></svg>';
const CHEV_DOWN = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
const X_MARK = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>';
const CHECK = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5 9-11"/></svg>';

let pinnedId = null;
let mode = 'sequence';
let durationUnit = 'seconds';
let rotationItems = []; // last-loaded Rotation, in order — drives the ↑/↓ moves
let sleepRanges = []; // up to three day-aware sleep windows (HANDOFF §13)
let manualBlank = false; // instant "Blank screen" override
let runningCommit = null; // the commit this player reports — used to detect the restart
let updateNeedsReboot = false; // the offered update touches the kiosk display → frame reboot needed (HANDOFF §15)
let collectionsList = []; // supported connected collections (from /api/collections)
let collectionsBySlug = {}; // slug → collection, for connected card subtitles
let cxSlug = null; // collection selected in the add-connected modal
let cxResolved = null; // last previewed { tokenId, title, image }

const fmtBytes = (n) => {
  if (n < 1024) return n + ' B';
  if (n < 1024 ** 2) return (n / 1024).toFixed(0) + ' KB';
  if (n < 1024 ** 3) return (n / 1024 ** 2).toFixed(1) + ' MB';
  return (n / 1024 ** 3).toFixed(2) + ' GB';
};

const sleepMs = (ms) => new Promise((r) => setTimeout(r, ms));
const escapeHtml = (s) =>
  String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

// Friendly build date from a short ISO "YYYY-MM-DD" — parsed by parts so there's no timezone
// drift, and locale-free so the offline frame always reads the same (HANDOFF §15).
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const fmtDate = (iso) => {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso || '');
  return m ? `${MONTHS[+m[2] - 1]} ${+m[3]}, ${m[1]}` : iso || '';
};

function setStatus(msg, sticky) {
  statusEl.textContent = msg || '';
  statusEl.hidden = !msg;
  statusEl.classList.toggle('show', !!sticky);
}

// A video card shows its first frame as a poster: the `#t=0.1` media fragment makes the
// browser seek ~0.1s in and paint that frame — no server-side thumbnail or transcode (§6).
const mediaTag = (item) =>
  item.kind === 'video'
    ? `<video src="/uploads/${item.filename}#t=0.1" muted playsinline preload="metadata"></video>`
    : `<img src="/uploads/${item.filename}" alt="" loading="lazy">`;

// Connected pieces show their cached preview image; everything else shows its own media (§6).
const thumbTag = (item) =>
  item.kind === 'connected'
    ? `<img src="${escapeHtml(item.thumb || '')}" alt="" loading="lazy">`
    : mediaTag(item);

// A connected collection that crops its art on the display (a per-collection `crop`) crops its
// thumbnail the same way, so the small preview shows the same region the frame does. Returns the
// zoom factor (1/crop) for that collection's slug, or 0 when it has no crop. The thumb container
// already clips; control.css zooms the image by --thumb-crop when the `crop` class is present.
const thumbCropScale = (slug) => {
  const c = collectionsBySlug[slug];
  return c && c.crop ? +(1 / c.crop).toFixed(4) : 0;
};

// ── Library tab ─────────────────────────────────────────────────────
function card(item) {
  const el = document.createElement('div');
  el.className = 'card';
  const isFill = item.fit === 'fill';
  const isPinned = item.id === pinnedId;
  const inRot = !!item.in_rotation;
  const connected = item.kind === 'connected';
  // Connected pieces: a "Connected" badge instead of a format chip, "by <Artist>" as the subtitle.
  // Most have no Fit/Fill (each collection's bundle sizes itself; render is decided per collection in
  // code), but a collection may opt in with `fitFill` (the Chromie Squiggle does), so its card shows the
  // toggle like a file. Otherwise a normal media card.
  const badge = connected ? '<span class="badge badge-connected">Connected</span>' : `<span class="badge">${item.format}</span>`;
  // Connected pieces show the artist's name as the subtitle (the official title may or may not embed
  // it: Brinkman's does, Kittoe's doesn't). Files show their size.
  const artistName = (collectionsBySlug[item.collection] || {}).artist || '';
  const sub = connected ? escapeHtml(artistName) : fmtBytes(item.bytes);
  const canFit = !connected || !!(collectionsBySlug[item.collection] || {}).fitFill;
  const fitBtn = canFit ? `<button class="fit" aria-pressed="${isFill}" title="How this piece fills the screen">${isFill ? 'Fill' : 'Fit'}</button>` : '';
  const cs = connected ? thumbCropScale(item.collection) : 0; // crop the thumbnail to match the cropped display
  el.innerHTML = `
    <div class="thumb fit-${canFit && isFill ? 'fill' : 'fit'}${cs ? ' crop' : ''}">
      ${thumbTag(item)}
      ${badge}
      <button class="rot-toggle${inRot ? ' on' : ''}" aria-pressed="${inRot}"
        aria-label="${inRot ? 'Remove from rotation' : 'Add to rotation'}"
        title="${inRot ? 'In the rotation — click to remove' : 'Add to the rotation'}">${inRot ? '✓' : '+'}</button>
      ${isPinned ? '<span class="pin-badge">📌 Pinned</span>' : ''}
    </div>
    <div class="meta">
      <span class="name" title="${escapeHtml(item.original_name)}">${escapeHtml(item.original_name)}</span>
      <span class="sub">${sub}</span>
    </div>
    <div class="actions">
      <button class="pin" aria-pressed="${isPinned}" title="Hold this piece on the screen permanently">${isPinned ? 'Pinned' : 'Pin'}</button>
      ${fitBtn}
      <button class="del">Delete</button>
    </div>`;
  // CSP (style-src 'self') blocks inline style attributes, so set the crop zoom via JS (like display.js).
  if (cs) el.querySelector('.thumb').style.setProperty('--thumb-crop', cs);
  el.querySelector('.rot-toggle').addEventListener('click', () => toggleRotation(item));
  el.querySelector('.pin').addEventListener('click', () => togglePin(item));
  const fitEl = el.querySelector('.fit');
  if (fitEl) fitEl.addEventListener('click', () => toggleFit(item));
  el.querySelector('.del').addEventListener('click', () => remove(item));
  return el;
}

async function loadLibrary() {
  const items = await fetch('/api/library').then((r) => r.json());
  grid.replaceChildren(...items.map(card));
  libCount.textContent = items.length ? String(items.length) : '';
  emptyEl.hidden = items.length > 0;
}

// ── Rotation tab ────────────────────────────────────────────────────
function rotRow(item, idx, total) {
  const el = document.createElement('div');
  el.className = 'rot-row';
  el.draggable = true;
  el.dataset.id = item.id;
  const isPinned = item.id === pinnedId;
  const cs = item.kind === 'connected' ? thumbCropScale(item.collection) : 0; // crop the thumbnail to match the cropped display
  el.innerHTML = `
    <span class="rot-grip" title="Drag to reorder">${GRIP}</span>
    <span class="rot-num">${idx + 1}</span>
    <span class="rot-thumb fit-${item.fit === 'fill' ? 'fill' : 'fit'}${cs ? ' crop' : ''}">${thumbTag(item)}</span>
    <span class="rot-meta">
      <span class="rot-name">${isPinned ? '<span class="rot-pin" title="Pinned">📌</span> ' : ''}${escapeHtml(item.original_name)}</span>
      <span class="rot-sub">${item.kind === 'connected' ? 'Connected' : item.format.toUpperCase() + (item.fit === 'fill' ? ' · Fill' : '')}</span>
    </span>
    <span class="rot-btns">
      <button class="up" ${idx === 0 ? 'disabled' : ''} aria-label="Move earlier">${CHEV_UP}</button>
      <button class="down" ${idx === total - 1 ? 'disabled' : ''} aria-label="Move later">${CHEV_DOWN}</button>
      <button class="rm" aria-label="Remove from rotation" title="Remove from rotation">${X_MARK}</button>
    </span>`;
  if (cs) el.querySelector('.rot-thumb').style.setProperty('--thumb-crop', cs); // CSP-safe crop zoom (see card())
  el.querySelector('.up').addEventListener('click', () => move(item.id, -1));
  el.querySelector('.down').addEventListener('click', () => move(item.id, 1));
  el.querySelector('.rm').addEventListener('click', () => toggleRotation(item));
  el.addEventListener('dragstart', () => el.classList.add('dragging'));
  el.addEventListener('dragend', () => { el.classList.remove('dragging'); commitOrder(); });
  return el;
}

async function loadRotation() {
  rotationItems = await fetch('/api/rotation').then((r) => r.json());
  const n = rotationItems.length;
  rotList.replaceChildren(...rotationItems.map((it, i) => rotRow(it, i, n)));
  rotCount.textContent = n ? String(n) : '';
  rotEmpty.hidden = n > 0;
  if (n > 1) {
    rotHint.hidden = false;
    rotHint.textContent =
      mode === 'shuffle'
        ? 'Shuffle plays these in a random order — the arrangement below sets the Sequence order.'
        : 'Plays top to bottom. Drag the handle, or use the arrows, to reorder.';
  } else {
    rotHint.hidden = true;
  }
}

async function toggleRotation(item) {
  await fetch(`/api/library/${item.id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ inRotation: !item.in_rotation }),
  });
  await refresh();
}

async function move(id, dir) {
  const ids = rotationItems.map((i) => i.id);
  const idx = ids.indexOf(id);
  const j = idx + dir;
  if (j < 0 || j >= ids.length) return;
  [ids[idx], ids[j]] = [ids[j], ids[idx]];
  await saveOrder(ids);
  await loadRotation();
}

async function commitOrder() {
  const ids = [...rotList.children].map((el) => Number(el.dataset.id));
  await saveOrder(ids);
  await loadRotation();
}

const saveOrder = (order) =>
  fetch('/api/rotation/order', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ order }),
  });

// Native drag-reorder (desktop pointer). On touch, the ↑/↓ arrows are the path.
function getDragAfterElement(y) {
  const rows = [...rotList.querySelectorAll('.rot-row:not(.dragging)')];
  return rows.reduce(
    (closest, child) => {
      const box = child.getBoundingClientRect();
      const offset = y - box.top - box.height / 2;
      if (offset < 0 && offset > closest.offset) return { offset, element: child };
      return closest;
    },
    { offset: -Infinity, element: null }
  ).element;
}

rotList.addEventListener('dragover', (e) => {
  e.preventDefault();
  const dragging = rotList.querySelector('.dragging');
  if (!dragging) return;
  const after = getDragAfterElement(e.clientY);
  if (after == null) rotList.appendChild(dragging);
  else rotList.insertBefore(dragging, after);
});

// ── Per-clip actions (shared by both tabs) ──────────────────────────
async function toggleFit(item) {
  const fit = item.fit === 'fill' ? 'fit' : 'fill';
  await fetch(`/api/library/${item.id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ fit }),
  });
  await refresh();
}

async function togglePin(item) {
  if (item.id === pinnedId) await fetch('/api/pin', { method: 'DELETE' });
  else await fetch(`/api/pin/${item.id}`, { method: 'PUT' });
  await refresh();
}

async function remove(item) {
  if (!confirm(`Delete "${item.original_name}" from the Library?\nThis removes the file from the frame.`)) return;
  await fetch(`/api/library/${item.id}`, { method: 'DELETE' });
  await refresh();
}

async function send(files) {
  if (!files || !files.length) return;
  const form = new FormData();
  [...files].forEach((f) => form.append('files', f));
  setStatus(`Uploading ${files.length} file${files.length > 1 ? 's' : ''}…`, true);
  const resp = await fetch('/api/upload', { method: 'POST', body: form });
  const res = await resp.json().catch(() => ({}));
  if (!resp.ok) {
    setStatus(res.error || `Upload failed (${resp.status}).`, true);
    return;
  }
  const added = res.added?.length || 0;
  const skipped = res.skipped || [];
  setStatus(
    `Added ${added}.` + (skipped.length ? ` Skipped ${skipped.length} unsupported: ${skipped.join(', ')}` : ''),
    true
  );
  await refresh();
}

// ── Rotation settings (global, equal-time) ──────────────────────────
function fromMs(ms) {
  if (ms % UNIT_MS.hours === 0) return { value: ms / UNIT_MS.hours, unit: 'hours' };
  if (ms % UNIT_MS.minutes === 0) return { value: ms / UNIT_MS.minutes, unit: 'minutes' };
  return { value: Math.max(1, Math.round(ms / 1000)), unit: 'seconds' };
}

function setSeg(container, attr, value) {
  container.querySelectorAll('button').forEach((b) => b.classList.toggle('on', b.dataset[attr] === value));
}

async function loadSettings() {
  const s = await fetch('/api/settings').then((r) => r.json());
  const d = fromMs(s.durationMs);
  durationEl.value = d.value;
  durationUnit = d.unit;
  setSeg(unitSeg, 'unit', durationUnit);
  mode = s.mode;
  setSeg(modeSeg, 'mode', mode);
  pinnedId = s.pinnedId;
  sleepRanges = (s.sleepRanges || []).map((r) => ({ start: r.start, end: r.end, days: Array.isArray(r.days) ? r.days.slice() : [] }));
  manualBlank = !!s.manualBlank;
  renderSleep();
  renderBlank();
  showReturnArt(!!s.retroArcade); // reflect the demo's runtime state (e.g. on reload while it runs)
}

const saveSettings = (patch) =>
  fetch('/api/settings', {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(patch),
  });

function pushDuration() {
  const value = Math.max(1, Math.round(Number(durationEl.value) || 1));
  durationEl.value = value;
  saveSettings({ durationMs: value * UNIT_MS[durationUnit] });
}

// ── Sleep Schedule (HANDOFF §13): up to three day-aware windows on a 12h clock ──
const pad2 = (n) => String(n).padStart(2, '0');
const clampInt = (v, lo, hi) => Math.min(hi, Math.max(lo, Math.round(Number(v) || lo)));
const toMin = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
const to24 = (h12, min, ap) => pad2((h12 % 12) + (ap === 'PM' ? 12 : 0)) + ':' + pad2(min);
const from24 = (hhmm) => { const [H, M] = hhmm.split(':').map(Number); return { h12: H % 12 || 12, min: M, ap: H >= 12 ? 'PM' : 'AM' }; };
const isOvernight = (r) => toMin(r.start) > toMin(r.end);
const fmtMin = (min) => { const h = Math.floor(min / 60) % 24, m = min % 60; return `${h % 12 || 12}:${pad2(m)}${h >= 12 ? 'pm' : 'am'}`; };
const MAX_SLEEP_RANGES = 3;
const DOW_LETTERS = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
const DOW_ABBR = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const DOW_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
// One window vs a day-of-week + clock minute. Overnight windows are anchored to the day they begin:
// the evening half belongs to that day, the after-midnight half to the day before.
const windowAsleep = (r, dow, nowMin) => {
  if (!r.days.length) return false;
  const s = toMin(r.start), e = toMin(r.end);
  if (s === e) return false;
  if (s < e) return r.days.includes(dow) && nowMin >= s && nowMin < e;
  if (nowMin >= s) return r.days.includes(dow);
  return nowMin < e && r.days.includes((dow + 6) % 7);
};
const asleepAt = (dow, nowMin) => sleepRanges.some((r) => windowAsleep(r, dow, nowMin));

function timeBlock(which, hhmm) {
  const t = from24(hhmm);
  return `<span class="time12 ${which}">
      <input class="t-h" type="number" min="1" max="12" inputmode="numeric" value="${t.h12}" aria-label="Hour">
      <span class="colon">:</span>
      <input class="t-m" type="number" min="0" max="59" inputmode="numeric" value="${pad2(t.min)}" aria-label="Minute">
      <span class="seg ampm" role="group" aria-label="AM or PM">
        <button type="button" data-ap="AM"${t.ap === 'AM' ? ' class="on"' : ''}>AM</button>
        <button type="button" data-ap="PM"${t.ap === 'PM' ? ' class="on"' : ''}>PM</button>
      </span>
    </span>`;
}

function sleepRow(r) {
  const el = document.createElement('div');
  const ov = isOvernight(r);
  el.className = 'sleep-row' + (r.days.length ? '' : ' off');
  el.innerHTML = `
    <div class="sleep-left">
      ${timeBlock('start', r.start)}
      <span class="to">→</span>
      ${timeBlock('end', r.end)}
      <span class="overnight"${ov ? '' : ' hidden'}>overnight</span>
    </div>
    <div class="sleep-right">
      <span class="sleep-daylabel">${ov ? 'Nights' : 'Days'}</span>
      <span class="sleep-days">${DOW_LETTERS.map((letter, d) => {
        const label = ov ? `${DOW_NAMES[d]} night` : DOW_NAMES[d];
        return `<button type="button" class="sleep-day${r.days.includes(d) ? ' on' : ''}" data-d="${d}" aria-pressed="${r.days.includes(d)}" aria-label="${label}" title="${label}">${letter}</button>`;
      }).join('')}</span>
      <button type="button" class="sleep-remove" aria-label="Remove this sleep time">${X_MARK}</button>
    </div>`;
  el.querySelectorAll('.t-h, .t-m').forEach((inp) =>
    inp.addEventListener('change', () => {
      inp.value = inp.classList.contains('t-h') ? clampInt(inp.value, 1, 12) : pad2(clampInt(inp.value, 0, 59));
      commitSleep();
    })
  );
  el.querySelectorAll('.ampm').forEach((seg) =>
    seg.querySelectorAll('button').forEach((b) =>
      b.addEventListener('click', () => { setSeg(seg, 'ap', b.dataset.ap); commitSleep(); })
    )
  );
  el.querySelectorAll('.sleep-day').forEach((b) =>
    b.addEventListener('click', () => {
      const on = b.getAttribute('aria-pressed') !== 'true';
      b.setAttribute('aria-pressed', String(on));
      b.classList.toggle('on', on);
      commitSleep();
    })
  );
  el.querySelector('.sleep-remove').addEventListener('click', () => {
    const rows = [...sleepRangesEl.querySelectorAll('.sleep-row')];
    sleepRanges = rows.map(readRow);
    sleepRanges.splice(rows.indexOf(el), 1);
    renderSleep();
    saveSettings({ sleepRanges });
  });
  return el;
}

const readTime = (block) =>
  to24(
    clampInt(block.querySelector('.t-h').value, 1, 12),
    clampInt(block.querySelector('.t-m').value, 0, 59),
    block.querySelector('.ampm .on')?.dataset.ap || 'AM'
  );
const readRow = (row) => ({
  start: readTime(row.querySelector('.time12.start')),
  end: readTime(row.querySelector('.time12.end')),
  days: [...row.querySelectorAll('.sleep-day')]
    .filter((b) => b.getAttribute('aria-pressed') === 'true')
    .map((b) => Number(b.dataset.d)),
});

function renderSleep() {
  sleepRangesEl.replaceChildren(...sleepRanges.map(sleepRow));
  sleepEmptyEl.hidden = sleepRanges.length > 0;
  sleepAddBtn.hidden = sleepRanges.length >= MAX_SLEEP_RANGES;
  renderStrip();
  renderSleepStatus();
}

// Append a new window: 10pm→6am, no days yet (inactive until the owner picks nights/days).
function addSleepTime() {
  sleepRanges = [...sleepRangesEl.querySelectorAll('.sleep-row')].map(readRow);
  if (sleepRanges.length >= MAX_SLEEP_RANGES) return;
  sleepRanges.push({ start: '22:00', end: '06:00', days: [] });
  renderSleep();
  saveSettings({ sleepRanges });
}

async function commitSleep() {
  const rows = [...sleepRangesEl.querySelectorAll('.sleep-row')];
  sleepRanges = rows.map(readRow);
  rows.forEach((row, i) => {
    const ov = isOvernight(sleepRanges[i]);
    row.querySelector('.overnight').hidden = !ov;
    row.querySelector('.sleep-daylabel').textContent = ov ? 'Nights' : 'Days';
    row.classList.toggle('off', sleepRanges[i].days.length === 0);
  });
  renderStrip();
  renderSleepStatus();
  await saveSettings({ sleepRanges });
}

// Header status, off the panel's own clock (the same signal the display flips on): reads
// "Sleeping until 7:00am" while asleep, "Awake until 10:00pm" otherwise (next boundary in the week).
function renderSleepStatus() {
  if (manualBlank) { sleepStatus.textContent = 'Blanked now'; return; }
  if (!sleepRanges.some((r) => r.days.length)) { sleepStatus.textContent = ''; return; }
  const now = new Date(), today = now.getDay(), nowMin = now.getHours() * 60 + now.getMinutes();
  const asleepNow = asleepAt(today, nowMin);
  let edge = null;
  for (let i = 1; i <= 7 * 1440; i++) {
    const tot = nowMin + i;
    if (asleepAt((today + Math.floor(tot / 1440)) % 7, tot % 1440) !== asleepNow) { edge = tot % 1440; break; }
  }
  sleepStatus.textContent = edge === null
    ? (asleepNow ? 'Sleeping' : '')
    : (asleepNow ? 'Sleeping until ' : 'Awake until ') + fmtMin(edge);
}

// Week-at-a-glance strip: one 24h bar per day, filled where the screen sleeps. The result is
// verifiable by eye, so nobody has to reason about which day an overnight window belongs to.
function sleepRuns(d) {
  const out = [];
  let start = null;
  for (let m = 0; m <= 1440; m++) {
    const asleep = m < 1440 && asleepAt(d, m);
    if (asleep && start === null) start = m;
    if (!asleep && start !== null) { out.push([start, m]); start = null; }
  }
  return out;
}

// Positions are set through the CSSOM (el.style.*), not inline style="" attributes, so the
// strict style-src CSP (server.js) stays intact: it blocks inline style attributes, not CSSOM.
function renderStrip() {
  sleepStripEl.replaceChildren();
  if (!sleepRanges.length) { sleepStripEl.hidden = true; return; }
  sleepStripEl.hidden = false;
  const now = new Date(), today = now.getDay(), nowMin = now.getHours() * 60 + now.getMinutes();
  const pct = (min) => (min / 1440 * 100).toFixed(2) + '%';
  const div = (cls, parent) => { const el = document.createElement('div'); el.className = cls; parent.appendChild(el); return el; };
  const span = (cls, parent, text) => { const el = document.createElement('span'); if (cls) el.className = cls; if (text != null) el.textContent = text; parent.appendChild(el); return el; };

  const ruler = div('ss-ruler', sleepStripEl);
  span('ss-spacer', ruler);
  const labels = div('ss-rulerlabels', ruler);
  [['12a', 0], ['6a', 25], ['12p', 50], ['6p', 75], ['12a', 100]].forEach(([t, p]) => {
    const s = span('', labels, t);
    if (p === 0) s.style.left = '0';
    else if (p === 100) s.style.right = '0';
    else { s.style.left = p + '%'; s.style.transform = 'translateX(-50%)'; }
  });

  for (let d = 0; d < 7; d++) {
    const row = div('ss-row', sleepStripEl);
    span('ss-label' + (d === today ? ' today' : ''), row, DOW_ABBR[d]);
    const bar = div('ss-bar', row);
    [25, 50, 75].forEach((p) => { div('ss-grid', bar).style.left = p + '%'; });
    for (const [s, e] of sleepRuns(d)) {
      const seg = div('ss-seg', bar);
      seg.style.left = pct(s);
      seg.style.width = pct(e - s);
    }
    if (d === today) div('ss-now', bar).style.left = pct(nowMin);
  }

  const legend = div('ss-legend', sleepStripEl);
  [['ss-sw-sleep', 'Sleeping'], ['ss-sw-art', 'Displaying'], ['ss-sw-now', 'Now']].forEach(([cls, text]) => {
    const item = span('', legend);
    span('ss-sw ' + cls, item);
    item.appendChild(document.createTextNode(text));
  });
}

function renderBlank() {
  blankBtn.setAttribute('aria-pressed', String(manualBlank));
  blankBtn.textContent = manualBlank ? 'Blanked' : 'Blank screen';
  renderSleepStatus();
}
async function toggleBlank() {
  manualBlank = !manualBlank;
  renderBlank();
  await saveSettings({ manualBlank });
}

// ── Software update (HANDOFF §15) — all browser-driven; never in the playback path ──
// Version line: number · friendly date · a small unlabeled commit fingerprint (links to GitHub).
// No "commit"/"tracking" jargon — the date is the human signal, the hash the precise one.
function renderVersion(s) {
  if (s.commit) runningCommit = s.commit;
  const parts = [];
  if (s.version) parts.push(escapeHtml(s.version));
  if (s.date) parts.push(escapeHtml(fmtDate(s.date)));
  let html = parts.join(' · ');
  if (s.commit) {
    const c = escapeHtml(s.commit);
    const tag = s.repoUrl
      ? `<a class="uv-commit" href="${escapeHtml(s.repoUrl)}/commit/${c}" target="_blank" rel="noopener" title="View this version on GitHub">${c}</a>`
      : `<span class="uv-commit">${c}</span>`;
    html += (html ? ' · ' : '') + tag;
  }
  updVersion.innerHTML = html || '—';
}

function setUpdStatus(html) {
  updStatus.innerHTML = html || '';
  updStatus.hidden = !html;
}
const showApply = (on) => { updApply.hidden = !on; }; // toggles the Update & Restart / Not now row

// Page-load status — no network, so it never blocks or fails (offline-safe).
async function loadUpdate() {
  const s = await fetch('/api/update').then((r) => r.json());
  renderVersion(s);
  if (s.unavailable === 'not-a-git-checkout') {
    setUpdStatus('Automatic updates aren’t available for this install.');
    checkUpdateBtn.disabled = true;
  }
}

async function checkUpdate() {
  checkUpdateBtn.disabled = true;
  showApply(false);
  setUpdStatus('Checking…');
  let s;
  try {
    s = await fetch('/api/update/check', { method: 'POST' }).then((r) => r.json());
  } catch {
    setUpdStatus('Couldn’t reach GitHub. Your art keeps playing — try again when you’re online.');
    checkUpdateBtn.disabled = false;
    return;
  }
  checkUpdateBtn.disabled = false;
  renderVersion(s);
  if (s.unavailable) return setUpdStatus('Automatic updates aren’t available for this install.');
  if (s.offline || !s.ok) {
    return setUpdStatus('Couldn’t reach GitHub. Your art keeps playing — try again when you’re online.');
  }
  if (!s.updateAvailable) {
    showApply(false);
    return setUpdStatus(s.note
      ? `You’re on the latest version. (${escapeHtml(s.note)})`
      : '<span class="upd-ok">✓</span> You’re up to date.');
  }
  if (s.diverged || !s.canFastForward) {
    showApply(false);
    return setUpdStatus(
      'An update is available, but this frame has local changes, so it can’t update automatically. Nothing was changed.'
    );
  }
  // Friendly date headline + the kept plain-English recap of what's in it. Subjects arrive as
  // "<short-hash> <message>"; drop the hash and show the message (HANDOFF §15, §20).
  const when = s.target && s.target.date ? ' · ' + escapeHtml(fmtDate(s.target.date)) : '';
  const list = (s.subjects || [])
    .slice(0, 6)
    .map((x) => `<li>${escapeHtml(x.replace(/^[0-9a-f]{7,40}\s+/i, ''))}</li>`)
    .join('');
  const link = s.compareUrl
    ? `<a class="upd-link" href="${escapeHtml(s.compareUrl)}" target="_blank" rel="noopener">What’s new ↗</a>`
    : '';
  updateNeedsReboot = !!s.requiresReboot; // remembered for after the restart (HANDOFF §15)
  setUpdStatus(
    `<div class="upd-headline">A newer version is available${when}</div>` +
      (list ? `<div class="upd-whats">What’s in it</div><ul class="upd-list">${list}</ul>` : '') +
      link +
      (s.requiresReboot ? '<div class="upd-reboot">After updating, reboot the frame to finish applying the display changes.</div>' : '') +
      (s.dirty ? '<div class="upd-warn">Heads-up: local file changes are present on this frame.</div>' : '')
  );
  showApply(true);
}

async function applyUpdate() {
  if (!confirm('Update OpenObject and restart the frame?\nThe frame briefly shows the OpenObject screen, then returns on the new version.')) return;
  applyUpdateBtn.disabled = true;
  checkUpdateBtn.disabled = true;
  setUpdStatus('Updating… the frame will briefly show the OpenObject screen.');
  const before = runningCommit;
  let res = null;
  try {
    res = await fetch('/api/update/apply', { method: 'POST' }).then((r) => r.json());
  } catch {
    // Connection dropped — almost certainly the restart itself. Recover by polling /healthz.
  }
  applyUpdateBtn.disabled = false;
  if (res && res.ok === false) {
    checkUpdateBtn.disabled = false;
    return setUpdStatus('Update couldn’t complete: ' + escapeHtml(res.error || 'unknown error') + ' Nothing was changed on the frame.');
  }
  if (res && res.upToDate) {
    checkUpdateBtn.disabled = false;
    showApply(false);
    return setUpdStatus('Already up to date.');
  }
  if (res && res.needsManualRestart) {
    checkUpdateBtn.disabled = false;
    showApply(false);
    return setUpdStatus('Updated. Restart the player to finish applying it.');
  }
  await waitForRestart(before); // restarting (or the request was cut off by the restart)
}

// "Not now" — dismiss the offered update without applying it; the version line stays put.
function dismissUpdate() {
  showApply(false);
  setUpdStatus('No problem — you can update any time from here.');
}

// ── Power & Wi-Fi (HANDOFF §10, §11) ────────────────────────────────
function setPowerStatus(html) {
  powerStatus.innerHTML = html || '';
  powerStatus.hidden = !html;
}

// Both power actions arm a cancellable countdown inline in the Power card (no native dialog) — a
// safety net against a misclick. Shut down especially: it can't be casually undone (you power the
// frame back on by replugging the outlet). At zero the action fires; Cancel aborts.
let countdownTimer = null;
function clearCountdown() {
  if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null; }
}
function armPowerAction(gerund, seconds, run) {
  clearCountdown();
  restartBtn.disabled = true;
  rebootBtn.disabled = true;
  shutdownBtn.disabled = true;
  let remaining = seconds;
  powerStatus.innerHTML =
    `${gerund} in <span id="countNum">${remaining}</span>s… <button type="button" class="update-btn power-cancel" id="cancelPowerBtn">Cancel</button>`;
  powerStatus.hidden = false;
  document.getElementById('cancelPowerBtn').addEventListener('click', cancelPowerAction);
  countdownTimer = setInterval(() => {
    remaining -= 1;
    if (remaining <= 0) {
      clearCountdown();
      run();
    } else {
      const el = document.getElementById('countNum');
      if (el) el.textContent = remaining;
    }
  }, 1000);
}
function cancelPowerAction() {
  clearCountdown();
  restartBtn.disabled = false;
  rebootBtn.disabled = false;
  shutdownBtn.disabled = false;
  setPowerStatus('Cancelled.');
}

// Real soft-restart via the supervisor — the same exit→relaunch as self-update. The version is
// unchanged, so we watch the boot id (not the commit) to confirm the player actually bounced.
async function doRestart() {
  setPowerStatus('Restarting… the control panel will be back in a moment.');
  let before = null;
  try { before = (await fetch('/healthz', { cache: 'no-store' }).then((r) => r.json())).boot; } catch {}
  let res = null;
  try { res = await fetch('/api/system/restart', { method: 'POST' }).then((r) => r.json()); } catch { /* dropped by the restart */ }
  if (res && res.needsManualRestart) {
    restartBtn.disabled = false; rebootBtn.disabled = false; shutdownBtn.disabled = false;
    return setPowerStatus('Restart isn’t available here — start the player with the supervisor (npm start) to enable it.');
  }
  const h = await pollHealthz((x) => x.boot && x.boot !== before);
  restartBtn.disabled = false; rebootBtn.disabled = false; shutdownBtn.disabled = false;
  if (h) {
    setPowerStatus('<span class="upd-ok">✓</span> Restarted — the control panel is back.');
    await refresh();
  } else {
    setPowerStatus('The control panel is taking longer than expected. It should come back on its own — reload this page in a moment.');
  }
}

// Reboot / Shut down are real on the installed frame (systemctl, via the polkit grant from
// install.sh) and inert stubs off-device, so the dev Mac is never touched. Each reports a clear
// message if the grant is not in place yet, and treats a dropped connection as the frame going
// down (HANDOFF §17).
async function doShutdown() {
  setPowerStatus('Shutting down the frame…');
  let res = null;
  try { res = await fetch('/api/system/shutdown', { method: 'POST' }).then((r) => r.json()); } catch { /* dropped: the frame is powering off */ }
  if (res && res.stub) {
    restartBtn.disabled = false; rebootBtn.disabled = false; shutdownBtn.disabled = false;
    return setPowerStatus(escapeHtml(res.message));
  }
  if (res && res.ok === false) {
    restartBtn.disabled = false; rebootBtn.disabled = false; shutdownBtn.disabled = false;
    return setPowerStatus('Couldn’t shut the frame down: ' + escapeHtml(res.error || 'unknown') + '. You can power-cycle at the outlet instead.');
  }
  // ok, or the connection dropped as it went down: the frame is powering off and will not return
  // until power is restored, so leave the buttons disabled.
  setPowerStatus('The frame is shutting down. Restore power at the outlet to turn it back on.');
}

async function doReboot() {
  setPowerStatus('Rebooting the frame…');
  let before = null;
  try { before = (await fetch('/healthz', { cache: 'no-store' }).then((r) => r.json())).boot; } catch {}
  let res = null;
  try { res = await fetch('/api/system/reboot', { method: 'POST' }).then((r) => r.json()); } catch { /* dropped: the frame is going down */ }
  if (res && res.stub) {
    restartBtn.disabled = false; rebootBtn.disabled = false; shutdownBtn.disabled = false;
    return setPowerStatus(escapeHtml(res.message));
  }
  if (res && res.ok === false) {
    restartBtn.disabled = false; rebootBtn.disabled = false; shutdownBtn.disabled = false;
    return setPowerStatus('Couldn’t reboot the frame: ' + escapeHtml(res.error || 'unknown') + '. You can power-cycle at the outlet instead.');
  }
  // ok, or a dropped connection: the whole frame is rebooting. A full OS reboot is slower than an
  // app restart, so wait a few minutes for it to come back, then refresh.
  setPowerStatus('Rebooting the frame… it should be back in about a minute.');
  const h = await pollHealthz((x) => x.boot && x.boot !== before, 180000);
  restartBtn.disabled = false; rebootBtn.disabled = false; shutdownBtn.disabled = false;
  if (h) { setPowerStatus('<span class="upd-ok">✓</span> The frame is back.'); await refresh(); }
  else setPowerStatus('The frame is rebooting and should be back shortly. Reload this page in a minute.');
}

// Show how to reach this panel from another device — real and useful today (HANDOFF §11).
async function loadSystem() {
  const s = await fetch('/api/system').then((r) => r.json()).catch(() => null);
  if (!s) return;
  const addrs = (s.addresses || []).map((ip) => {
    // Omit the port for plain http (:80) so the frame shows a clean http://<ip> (HANDOFF §11).
    const url = `http://${ip}${s.port && Number(s.port) !== 80 ? ':' + s.port : ''}`;
    return `<a href="${escapeHtml(url)}" target="_blank" rel="noopener">${escapeHtml(url)}</a>`;
  });
  frameAddr.innerHTML = addrs.join(' or ') || '—';
  const reachMdns = document.getElementById('reachMdns');
  if (s.mdns) { frameMdns.textContent = s.mdns; frameMdns.href = `http://${s.mdns}`; reachMdns.hidden = false; }
  else reachMdns.hidden = true;
  reachEl.hidden = addrs.length === 0 && !s.mdns;
}

// Poll /healthz until the player is back up and a predicate holds (a new commit after an update,
// or a new boot id after a plain restart). Returns the payload, or null on timeout. Shared by the
// self-update and Restart flows (HANDOFF §10, §15).
async function pollHealthz(isBack, timeoutMs = 90000) {
  const started = Date.now();
  await sleepMs(1200); // give it a moment to actually go down first
  while (Date.now() - started < timeoutMs) {
    try {
      const h = await fetch('/healthz', { cache: 'no-store' }).then((r) => r.json());
      if (h && h.ok && isBack(h)) return h;
    } catch { /* still down — keep polling */ }
    await sleepMs(1500);
  }
  return null;
}

async function waitForRestart(before) {
  setUpdStatus('Updating… waiting for the frame to come back.');
  const h = await pollHealthz((x) => x.commit && x.commit !== before);
  checkUpdateBtn.disabled = false;
  if (h) {
    showApply(false);
    if (updateNeedsReboot) {
      // The display page changed, so the kiosk needs a frame reboot to reload it. Keep the reminder
      // visible (Reboot is in the Power controls) rather than auto-reloading the panel away from it.
      setUpdStatus('<span class="upd-ok">✓</span> Updated. Reboot the frame to finish applying the display changes — use Reboot in the Power controls below.');
      await refresh();
      await loadUpdate(); // refresh the version line to the new number · date · commit
    } else {
      // Reload so the new control-panel code actually shows: the assets revalidate on reload (served
      // max-age=0 + ETag), so the browser fetches the new control.js/.css instead of the old in-memory
      // copy. The page never reloading (only the version line did) is what made changes look missing.
      setUpdStatus('<span class="upd-ok">✓</span> Updated — refreshing…');
      setTimeout(() => location.reload(), 900);
    }
  } else {
    setUpdStatus('The frame is taking longer than expected. It should come back on its own — reload this page in a moment.');
  }
}

// loadSettings first (it sets pinnedId/mode the renderers read), then the two lists.
async function refresh() {
  // loadSettings sets pinnedId/mode and loadCollections fills collectionsBySlug — both are read
  // by the library/rotation renderers, so they run first.
  await Promise.all([loadSettings(), loadCollections()]);
  await Promise.all([loadLibrary(), loadRotation()]);
}

// ── Connected collections ────────────────────────────
async function loadCollections() {
  try { collectionsList = await fetch('/api/collections').then((r) => r.json()); }
  catch { collectionsList = []; }
  collectionsBySlug = {};
  collectionsList.forEach((c) => { collectionsBySlug[c.slug] = c; });
  renderConnectedCard();
}

// Settings → Connected Collections: the supported list, each with Animate + Hide.
function renderConnectedCard() {
  const total = collectionsList.length, hidden = collectionsList.filter((c) => c.hidden).length;
  ccCount.textContent = total ? `${total} collection${total === 1 ? '' : 's'}${hidden ? ` · ${hidden} hidden` : ''}` : '';
  ccUnhideAll.hidden = !collectionsList.some((c) => c.hidden);
  if (!collectionsList.length) {
    connectedList.innerHTML = '<p class="cc-empty">No connected collections are supported yet.</p>';
    return;
  }
  connectedList.replaceChildren(...collectionsList.map((c) => {
    const row = document.createElement('div');
    row.className = 'cc-row' + (c.hidden ? ' is-hidden' : '');
    // A collection's controls, rendered in order. These are no longer mutually exclusive: the Chromie
    // Squiggle carries both a 0–10 speed slider (0 = still) and a Background dropdown, shown in that order.
    // A speedControl piece (auto-animated at a chosen pace) gets the slider; a choice piece (a curated set
    // of modes, e.g. the squiggle's White/Black background) gets a dropdown; an Animate-on-load piece (with
    // no speed/choice) gets the on/off switch; a time-aware still (animatable:false) gets none.
    const ctls = [];
    if (c.speedControl) {
      const v = c.speed == null ? 0 : c.speed;
      ctls.push(`<span class="cc-speed">
        <span class="cc-speed-label">Motion <span class="cc-speed-val">${v === 0 ? 'Off' : v}</span></span>
        <input class="cc-speed-range" type="range" min="0" max="${c.speedMax || 10}" step="1" value="${v}" aria-label="Motion speed for ${escapeHtml(c.name)}">
      </span>`);
    }
    if (c.choice) {
      const opts = c.choice.options
        .map((o) => `<option value="${escapeHtml(o.value)}"${String(o.value) === String(c.choice.value) ? ' selected' : ''}>${escapeHtml(o.label)}</option>`)
        .join('');
      ctls.push(`<span class="cc-choice">
        <span class="cc-choice-label">${escapeHtml(c.choice.label)}</span>
        <select class="cc-choice-select" aria-label="${escapeHtml(c.choice.label)} for ${escapeHtml(c.name)}">${opts}</select>
      </span>`);
    }
    // General multi-control model: render each declared control (a range slider or a select) in order. Wired
    // below by data-cc-key, so several ranges/selects on one row each patch their own key independently.
    if (Array.isArray(c.controls)) {
      for (const ctl of c.controls) {
        const v = ctl.value == null ? ctl.default : ctl.value;
        if (ctl.type === 'range') {
          ctls.push(`<span class="cc-ctrl" data-cc-key="${escapeHtml(ctl.key)}">
            <span class="cc-ctrl-label">${escapeHtml(ctl.label)} <span class="cc-ctrl-val">${escapeHtml(String(v))}${escapeHtml(ctl.suffix || '')}</span></span>
            <input class="cc-ctrl-range" type="range" min="${ctl.min}" max="${ctl.max}" step="${ctl.step}" value="${v}" aria-label="${escapeHtml(ctl.label)} for ${escapeHtml(c.name)}">
          </span>`);
        } else if (ctl.type === 'select') {
          const copts = ctl.options
            .map((o) => `<option value="${escapeHtml(o.value)}"${String(o.value) === String(v) ? ' selected' : ''}>${escapeHtml(o.label)}</option>`)
            .join('');
          ctls.push(`<span class="cc-ctrl" data-cc-key="${escapeHtml(ctl.key)}">
            <span class="cc-ctrl-label">${escapeHtml(ctl.label)}</span>
            <select class="cc-ctrl-select" aria-label="${escapeHtml(ctl.label)} for ${escapeHtml(c.name)}">${copts}</select>
          </span>`);
        }
      }
    }
    if (c.animatable !== false) {
      ctls.push(`<span class="cc-animate">Animate <button class="cc-switch${c.animate ? ' on' : ''}" role="switch" aria-checked="${c.animate}" aria-label="Animate ${escapeHtml(c.name)}"></button></span>`);
    }
    const motionCtl = ctls.join('');
    // The controls (one or several) wrap in `.cc-controls`; control.css lays them out by screen width, not
    // by count — inline beside the name on a wide panel, dropped to their own right-aligned row 2 on a
    // narrow one (phones) so a long name keeps the full width. An empty `.cc-controls` collapses away.
    row.innerHTML = `
      <span class="cc-meta">
        <span class="cc-name">${escapeHtml(c.name)}</span>
        <span class="cc-sub">by ${escapeHtml(c.artist)} · ${c.pieces} piece${c.pieces === 1 ? '' : 's'}</span>
      </span>
      <span class="cc-controls">${motionCtl}</span>
      <button class="cc-hide">${c.hidden ? 'Unhide' : 'Hide'}</button>`;
    const sw = row.querySelector('.cc-switch');
    if (sw) sw.addEventListener('click', () => patchCollection(c.slug, { animate: !c.animate }));
    const sel = row.querySelector('.cc-choice-select');
    if (sel) sel.addEventListener('change', () => patchCollection(c.slug, { choice: sel.value }));
    const range = row.querySelector('.cc-speed-range');
    if (range) {
      const valEl = row.querySelector('.cc-speed-val');
      // Update the label live as the slider moves; save on release (the display polls the change in).
      range.addEventListener('input', () => { valEl.textContent = Number(range.value) === 0 ? 'Off' : range.value; });
      range.addEventListener('change', () => patchCollection(c.slug, { speed: Number(range.value) }));
    }
    // General controls: each .cc-ctrl carries its key; wire its range or select to patch just that key.
    row.querySelectorAll('.cc-ctrl').forEach((el) => {
      const key = el.getAttribute('data-cc-key');
      const def = (c.controls || []).find((d) => d.key === key) || {};
      const r = el.querySelector('.cc-ctrl-range');
      if (r) {
        const valEl = el.querySelector('.cc-ctrl-val');
        r.addEventListener('input', () => { valEl.textContent = r.value + (def.suffix || ''); });
        r.addEventListener('change', () => patchCollection(c.slug, { controls: { [key]: Number(r.value) } }));
      }
      const s = el.querySelector('.cc-ctrl-select');
      if (s) s.addEventListener('change', () => patchCollection(c.slug, { controls: { [key]: s.value } }));
    });
    row.querySelector('.cc-hide').addEventListener('click', () => patchCollection(c.slug, { hidden: !c.hidden }));
    return row;
  }));
}

async function patchCollection(slug, patch) {
  await fetch(`/api/collections/${slug}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(patch) });
  await loadCollections();
  await loadRotation(); // animate/visibility changes can affect the display + the rotation sub
}

async function unhideAll() {
  for (const c of collectionsList) {
    if (c.hidden) await fetch(`/api/collections/${c.slug}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ hidden: false }) });
  }
  await loadCollections();
}

// The add modal: pick a collection, enter the Token ID, preview the derived piece, add it.
function cxStatus(text, isError) {
  cxMsg.textContent = text || '';
  cxMsg.hidden = !text;
  cxMsg.style.color = isError ? 'var(--danger)' : 'var(--muted)';
}

function openConnected() {
  cxSlug = null; cxResolved = null;
  cxToken.value = '';
  cxResult.hidden = true; cxStatus(''); cxAdd.disabled = true;
  renderPicker();
  maybeAutoPreview();                       // a fixed-token collection resolves its one piece up front
  cxOverlay.hidden = false;
  if (!cxToken.hidden) setTimeout(() => cxToken.focus(), 0);
}
const closeConnected = () => { cxOverlay.hidden = true; };

function renderPicker() {
  const visible = collectionsList.filter((c) => !c.hidden);
  if (!visible.length) {
    cxCollections.innerHTML = '<p class="cc-empty">No collections available — unhide one in Settings.</p>';
    cxAdd.disabled = true;
    return;
  }
  if (!cxSlug || !visible.some((c) => c.slug === cxSlug)) cxSlug = visible[0].slug; // default-select first
  cxCollections.replaceChildren(...visible.map((c) => {
    const row = document.createElement('div');
    row.className = 'cx-col' + (c.slug === cxSlug ? ' sel' : '');
    row.innerHTML = `
      <span class="cx-col-text">
        <span class="cx-col-art">${escapeHtml(c.name)}</span>
        <span class="cx-col-sub">${escapeHtml(c.artist)}</span>
      </span>
      <span class="cx-col-check">✓</span>`;
    row.addEventListener('click', () => { cxSlug = c.slug; resetResolve(); renderPicker(); maybeAutoPreview(); });
    return row;
  }));
  syncTokenInput();
}

// Small info glyph for the "Supported Token IDs" hint (recolored via CSS, like the other panel icons).
const INFO_ICON = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 16v-4"></path><path d="M12 8h.01"></path></svg>';

// A fixedToken collection supports a single piece, so the Token ID field is hidden and the piece is
// resolved automatically; every other collection shows the field and waits for a Token ID.
function syncTokenInput() {
  const c = collectionsBySlug[cxSlug] || {};
  const fixed = !!c.fixedToken;
  cxTokenLabel.hidden = fixed;
  cxToken.hidden = fixed;
  // Always-visible "Supported Token IDs" hint for collections restricted to specific IDs (a fixedToken's one
  // id, or a curated subset like Lost in Moffat County's 3,4,5,6). Open collections list nothing, so no hint.
  const ids = c.supportedTokens;
  if (ids && ids.length) {
    cxSupported.innerHTML = `${INFO_ICON}<span>Supported Token IDs: <span class="cx-supported-ids">${ids.map(escapeHtml).join(', ')}</span></span>`;
    cxSupported.hidden = false;
  } else {
    cxSupported.hidden = true;
  }
}
function maybeAutoPreview() {
  if ((collectionsBySlug[cxSlug] || {}).fixedToken) previewToken();
}

function resetResolve() { cxResolved = null; cxResult.hidden = true; cxStatus(''); cxAdd.disabled = true; }

async function previewToken() {
  resetResolve();
  const tokenId = (collectionsBySlug[cxSlug] || {}).fixedToken || cxToken.value.trim();
  if (!cxSlug || !tokenId) return;
  cxStatus('Looking up…');
  let r, j;
  try {
    r = await fetch(`/api/collections/${cxSlug}/preview`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tokenId }) });
    j = await r.json().catch(() => ({}));
  } catch { return cxStatus('Network error — try again.', true); }
  if (!r.ok) return cxStatus(j.error || 'Could not find that piece.', true);
  cxStatus('');
  cxResolved = j;
  const col = collectionsBySlug[cxSlug] || {};
  const cs = thumbCropScale(cxSlug); // crop the preview to match the cropped display
  cxResult.innerHTML =
    (j.image ? `<span class="cx-rthumb${cs ? ' crop' : ''}"><img src="${escapeHtml(j.image)}" alt=""></span>` : '') +
    `<span class="cx-rtext">
       <span class="cx-rtitle">${escapeHtml(j.title)}</span>
       <span class="cx-rsub">${escapeHtml(col.artist || '')} · ${escapeHtml(col.name || '')}</span>
     </span>`;
  cxResult.hidden = false;
  // CSP (style-src 'self') blocks inline style attributes, so set the crop zoom via JS (like display.js).
  if (cs && j.image) cxResult.querySelector('.cx-rthumb').style.setProperty('--thumb-crop', cs);
  cxAdd.disabled = false;
}

async function addConnected() {
  if (!cxSlug || !cxResolved) return;
  cxAdd.disabled = true;
  cxStatus('Adding…');
  let r, j;
  try {
    r = await fetch(`/api/collections/${cxSlug}/add`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ tokenId: cxResolved.tokenId }) });
    j = await r.json().catch(() => ({}));
  } catch { cxAdd.disabled = false; return cxStatus('Network error — try again.', true); }
  if (!r.ok) { cxAdd.disabled = false; return cxStatus(j.error || 'Could not add the piece.', true); }
  closeConnected();
  switchTab('library');
  await refresh();
}

// ── Tabs ────────────────────────────────────────────────────────────
const TABS = {
  library: [tabLibrary, panelLibrary],
  rotation: [tabRotation, panelRotation],
  settings: [tabSettings, panelSettings],
};
function switchTab(name) {
  // Don't carry a transient power message (countdown, "Restarted…", "Cancelled") across tabs,
  // and never leave a power countdown ticking on a hidden tab.
  clearCountdown();
  restartBtn.disabled = false;
  shutdownBtn.disabled = false;
  setPowerStatus('');
  for (const [key, [tab, panel]] of Object.entries(TABS)) {
    const on = key === name;
    tab.setAttribute('aria-selected', String(on));
    panel.hidden = !on;
  }
}
Object.keys(TABS).forEach((name) => TABS[name][0].addEventListener('click', () => switchTab(name)));

// ── Wiring ──────────────────────────────────────────────────────────
durDown.addEventListener('click', () => { durationEl.value = Math.max(1, (Number(durationEl.value) || 1) - 1); pushDuration(); });
durUp.addEventListener('click', () => { durationEl.value = (Number(durationEl.value) || 0) + 1; pushDuration(); });
durationEl.addEventListener('change', pushDuration);

unitSeg.querySelectorAll('button').forEach((b) =>
  b.addEventListener('click', () => { durationUnit = b.dataset.unit; setSeg(unitSeg, 'unit', durationUnit); pushDuration(); })
);
modeSeg.querySelectorAll('button').forEach((b) =>
  b.addEventListener('click', () => { mode = b.dataset.mode; setSeg(modeSeg, 'mode', mode); saveSettings({ mode }); loadRotation(); })
);
blankBtn.addEventListener('click', toggleBlank);
sleepAddBtn.addEventListener('click', addSleepTime);

// ── Retro Arcade (hidden easter egg) ────────────────────────────────
// A secret key sequence flips the display into the self-playing demo; Return to Art (shown only while
// it runs) flips it back. The server flag is runtime-only, so the frame never wakes into the demo.
// Nothing here names the sequence or the demo on the panel — Return to Art is the lone affordance.
const ARCADE_CODE = ['ArrowUp', 'ArrowUp', 'ArrowDown', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'ArrowLeft', 'ArrowRight', 'b', 'a'];
let arcadeCodePos = 0;
function showReturnArt(on) { returnArtBtn.hidden = !on; }
async function startArcade() { try { await fetch('/api/arcade', { method: 'PUT' }); } catch {} showReturnArt(true); }
async function stopArcade() { try { await fetch('/api/arcade', { method: 'DELETE' }); } catch {} showReturnArt(false); }
window.addEventListener('keydown', (e) => {
  const tag = (e.target && e.target.tagName) || '';
  if (tag === 'INPUT' || tag === 'TEXTAREA' || (e.target && e.target.isContentEditable)) return; // not while typing
  const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
  arcadeCodePos = key === ARCADE_CODE[arcadeCodePos] ? arcadeCodePos + 1 : (key === ARCADE_CODE[0] ? 1 : 0);
  if (arcadeCodePos === ARCADE_CODE.length) { arcadeCodePos = 0; startArcade(); }
});
returnArtBtn.addEventListener('click', stopArcade);

// Collapsible Settings cards (HANDOFF §13): clicking the header folds the body away. The four
// collapsible cards (Sleep Schedule, Connected Collections, Password, Wi-Fi) start closed to keep
// the Settings tab short; the open/closed choice is then remembered per browser (localStorage), so
// a card the owner opens stays open until they close it again, across reloads and auto-updates.
function wireCollapse(cardId, toggleId) {
  const card = document.getElementById(cardId), btn = document.getElementById(toggleId);
  const key = 'oo.collapsed.' + cardId;
  const apply = (collapsed) => {
    card.classList.toggle('is-collapsed', collapsed);
    btn.setAttribute('aria-expanded', String(!collapsed));
  };
  let stored = null;
  try { stored = localStorage.getItem(key); } catch { /* storage off: default closed */ }
  apply(stored !== '0');  // closed by default, and unless the owner has explicitly opened it ("0")
  btn.addEventListener('click', () => {
    const collapsed = card.classList.toggle('is-collapsed');
    btn.setAttribute('aria-expanded', String(!collapsed));
    try { localStorage.setItem(key, collapsed ? '1' : '0'); } catch { /* storage off: in-memory only */ }
  });
}
wireCollapse('sleepCard', 'sleepToggle');
wireCollapse('connectedCard', 'connectedToggle');
wireCollapse('wifiCard', 'wifiToggle');

// Keep the Sleep Schedule status line and the week strip's "now" marker current as time passes.
setInterval(() => { if (!panelSettings.hidden) { renderSleepStatus(); renderStrip(); } }, 60000);

checkUpdateBtn.addEventListener('click', checkUpdate);
applyUpdateBtn.addEventListener('click', applyUpdate);
dismissUpdateBtn.addEventListener('click', dismissUpdate);
restartBtn.addEventListener('click', () => armPowerAction('Restarting', 5, doRestart));
rebootBtn.addEventListener('click', () => armPowerAction('Rebooting', 10, doReboot));
shutdownBtn.addEventListener('click', () => armPowerAction('Shutting down', 10, doShutdown));

drop.addEventListener('click', () => fileInput.click());
drop.addEventListener('keydown', (e) => {
  if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); fileInput.click(); }
});
fileInput.addEventListener('change', () => { send(fileInput.files); fileInput.value = ''; });

['dragenter', 'dragover'].forEach((ev) =>
  drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.add('drag'); })
);
['dragleave', 'drop'].forEach((ev) =>
  drop.addEventListener(ev, (e) => { e.preventDefault(); drop.classList.remove('drag'); })
);
drop.addEventListener('drop', (e) => send(e.dataTransfer.files));

// Connected artwork: entry button → modal; Token ID resolves on change/Enter.
addConnectedBtn.addEventListener('click', openConnected);
cxClose.addEventListener('click', closeConnected);
cxOverlay.addEventListener('click', (e) => { if (e.target === cxOverlay) closeConnected(); });
cxToken.addEventListener('change', previewToken);
cxToken.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); previewToken(); } });
cxAdd.addEventListener('click', addConnected);
ccUnhideAll.addEventListener('click', unhideAll);

// ── Optional password (HANDOFF §10) ─────────────────────────────────
// Off by default. /api/auth/status reports whether a password is set and whether this browser is
// logged in; when it's required and we're not, show the login overlay and load nothing protected
// until the owner logs in. The kiosk/display is unaffected (its routes stay open server-side).
let authState = { required: false, authed: true };

async function loadAuth() {
  authState = await fetch('/api/auth/status').then((r) => r.json()).catch(() => ({ required: false, authed: true }));
  renderAuthCard();
  return authState;
}

function authCardMsg(text) {
  const m = authCard.querySelector('.auth-msg');
  if (m) { m.textContent = text || ''; m.hidden = !text; }
}

// Settings → Password card: reflects the current state and offers the matching actions.
// Set/change asks for the password twice (it's masked, so a typo would otherwise lock the owner out).
function renderAuthCard() {
  if (!authState.required) {
    authCard.innerHTML = `
      <div class="card-head">
        <button type="button" class="card-toggle" id="authToggle" aria-expanded="true" aria-controls="authBody">
          <span class="card-chev" aria-hidden="true">${CHEV_DOWN}</span>
          <span class="section-title">Password</span>
        </button>
      </div>
      <div class="card-body" id="authBody">
        <p class="device-note device-note-block">The control panel is open to anyone on your network. Optionally set a password. This will not affect the display of art.</p>
        <div class="auth-fields">
          <input id="setPw" class="auth-input" type="password" autocomplete="new-password" placeholder="New password">
          <input id="setPwConfirm" class="auth-input" type="password" autocomplete="new-password" placeholder="Confirm password">
        </div>
        <div class="auth-row">
          <button type="button" id="setPwBtn" class="update-btn">Set password</button>
        </div>
        <div class="auth-msg" hidden></div>
      </div>`;
    authCard.querySelector('#setPwBtn').addEventListener('click', () =>
      setOrChangePassword(authCard.querySelector('#setPw'), authCard.querySelector('#setPwConfirm'), 'Password protection is on.'));
  } else {
    authCard.innerHTML = `
      <div class="card-head">
        <button type="button" class="card-toggle" id="authToggle" aria-expanded="true" aria-controls="authBody">
          <span class="card-chev" aria-hidden="true">${CHEV_DOWN}</span>
          <span class="section-title">Password</span>
        </button>
      </div>
      <div class="card-body" id="authBody">
        <p class="device-note device-note-block">Password protection is <strong>on</strong>. The control panel asks for it before any changes; the display is unaffected.</p>
        <div class="auth-fields">
          <input id="newPw" class="auth-input" type="password" autocomplete="new-password" placeholder="New password">
          <input id="newPwConfirm" class="auth-input" type="password" autocomplete="new-password" placeholder="Confirm password">
        </div>
        <div class="device-row">
          <button type="button" id="changePwBtn" class="update-btn">Change password</button>
          <button type="button" id="logoutBtn" class="update-btn">Log out</button>
          <button type="button" id="offPwBtn" class="update-btn danger">Turn off password</button>
        </div>
        <div class="auth-msg" hidden></div>
      </div>`;
    authCard.querySelector('#changePwBtn').addEventListener('click', () =>
      setOrChangePassword(authCard.querySelector('#newPw'), authCard.querySelector('#newPwConfirm'), 'Password changed.'));
    authCard.querySelector('#logoutBtn').addEventListener('click', logout);
    authCard.querySelector('#offPwBtn').addEventListener('click', turnOffPassword);
  }
  wireCollapse('authCard', 'authToggle');
}

async function setOrChangePassword(pwInput, confirmInput, okMsg) {
  if (pwInput.value !== confirmInput.value) return authCardMsg("Those passwords don't match.");
  const r = await fetch('/api/auth/password', {
    method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password: pwInput.value }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) return authCardMsg(j.error || 'Could not save the password.');
  pwInput.value = ''; confirmInput.value = '';
  await loadAuth();   // re-render in the new state (a fresh cookie keeps us logged in)
  authCardMsg(okMsg);
}

async function turnOffPassword() {
  if (!confirm('Turn off the password? Anyone on your network will be able to control the frame again.')) return;
  const r = await fetch('/api/auth/password', { method: 'DELETE' });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) return authCardMsg(j.error || 'Could not turn it off.');
  await loadAuth();
  authCardMsg('Password protection is off.');
}

async function logout() {
  await fetch('/api/auth/logout', { method: 'POST' }).catch(() => {});
  location.reload(); // comes back to the login overlay
}

function showLogin(show) {
  loginOverlay.hidden = !show;
  if (show) setTimeout(() => authPw.focus(), 0);
}

loginForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  authMsg.hidden = true;
  const r = await fetch('/api/auth/login', {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ password: authPw.value }),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) { authMsg.textContent = j.error || 'Wrong password.'; authMsg.hidden = false; authPw.select(); return; }
  authPw.value = '';
  showLogin(false);
  loadPanel();
});

// Everything behind the gate: run once we know we're authed (or on a frame with no password).
function loadPanel() {
  refresh();
  loadUpdate(); // self-update status is independent of the library/rotation refresh
  loadSystem(); // power/Wi-Fi card: reachable addresses
}

// Boot: check auth first, then either show the login overlay or load the panel.
async function init() {
  await loadAuth();
  if (authState.required && !authState.authed) return showLogin(true);
  showLogin(false);
  loadPanel();
}
init();

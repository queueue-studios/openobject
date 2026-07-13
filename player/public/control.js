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
const libView = document.getElementById('libView');     // Library view controls (tab row; Library tab only)
const filterSelect = document.getElementById('filterSelect');
const sortSelect = document.getElementById('sortSelect');

const durationEl = document.getElementById('duration');
const durDown = document.getElementById('durDown');
const durUp = document.getElementById('durUp');
const unitSeg = document.getElementById('unitSeg');
const modeSeg = document.getElementById('modeSeg');
const hostNameEl = document.getElementById('hostName');

const tabLibrary = document.getElementById('tabLibrary');
const tabRotation = document.getElementById('tabRotation');
const tabSettings = document.getElementById('tabSettings');
const panelLibrary = document.getElementById('panelLibrary');
const panelRotation = document.getElementById('panelRotation');
const panelSettings = document.getElementById('panelSettings');
const rotList = document.getElementById('rotList');
const rotCount = document.getElementById('rotCount');
const rotEmpty = document.getElementById('rotEmpty');

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
const updateCard = document.querySelector('section.update'); // whole Software Update card (git-pull)

const restartBtn = document.getElementById('restartBtn');
const shutdownBtn = document.getElementById('shutdownBtn');
const rebootBtn = document.getElementById('rebootBtn');
const powerStatus = document.getElementById('powerStatus');
const reachEl = document.getElementById('reach');
const frameAddr = document.getElementById('frameAddr');
const aboutVersion = document.getElementById('aboutVersion');

const loginOverlay = document.getElementById('loginOverlay');
const loginForm = document.getElementById('loginForm');
const authPw = document.getElementById('authPw');
const authMsg = document.getElementById('authMsg');
const authCard = document.getElementById('authCard');

// Connected artwork: entry button, add modal, and the Settings collections card.
const addConnectedBtn = document.getElementById('addConnected');
const cxOverlay = document.getElementById('cxOverlay');
const cxBox = document.getElementById('cxBox');
const cxClose = document.getElementById('cxClose');
const cxCollections = document.getElementById('cxCollections');
const cxToken = document.getElementById('cxToken');
const cxTokenLabel = document.getElementById('cxTokenLabel');
const cxSupported = document.getElementById('cxSupported');
const cxResult = document.getElementById('cxResult');
const cxMsg = document.getElementById('cxMsg');
const cxAdd = document.getElementById('cxAdd');
const cxCancel = document.getElementById('cxCancel');
const connectedList = document.getElementById('connectedList');
const ccUnhideAll = document.getElementById('ccUnhideAll');
const ccCount = document.getElementById('ccCount');

// Folder Collections (HANDOFF §17): the Rotation-tab source control + the Settings card + the picker.
const sourceSelect = document.getElementById('sourceSelect');
const orderGroup = document.getElementById('orderGroup');
const folderSummary = document.getElementById('folderSummary');
const foldersListEl = document.getElementById('foldersList');
const fcCount = document.getElementById('fcCount');
const fcAddBtn = document.getElementById('fcAddBtn');
const fcHint = document.getElementById('fcHint');
const fpOverlay = document.getElementById('fpOverlay');
const fpBox = document.getElementById('fpBox');
const fpPath = document.getElementById('fpPath');
const fpList = document.getElementById('fpList');
const fpCurrent = document.getElementById('fpCurrent');
const fpMsg = document.getElementById('fpMsg');
const fpClose = document.getElementById('fpClose');
const fpCancel = document.getElementById('fpCancel');
const fpUse = document.getElementById('fpUse');

const UNIT_MS = { seconds: 1000, minutes: 60000, hours: 3600000 };

// Inline icons (no webfont dependency — the frame runs offline).
const GRIP = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true"><circle cx="5" cy="4" r="1.3"/><circle cx="11" cy="4" r="1.3"/><circle cx="5" cy="8" r="1.3"/><circle cx="11" cy="8" r="1.3"/><circle cx="5" cy="12" r="1.3"/><circle cx="11" cy="12" r="1.3"/></svg>';
const CHEV_UP = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 15l6-6 6 6"/></svg>';
const CHEV_DOWN = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
const X_MARK = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>';
const CHECK = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M5 12l5 5 9-11"/></svg>';

let pinnedId = null;
let mode = 'sequence';
let librarySort = 'recent'; // Library grid order: recent (default) | oldest | title | artist (HANDOFF §7)
let libraryFilter = 'all';  // Library view filter: all (default) | rotation — hides not-in-rotation pieces (HANDOFF §7)
let durationUnit = 'seconds';
let rotationItems = []; // last-loaded Rotation, in order — drives the ↑/↓ moves
let sleepRanges = []; // up to three day-aware sleep windows (HANDOFF §13)
let manualBlank = false; // manual Sleep: off until woken
let wakeUntil = 0;       // manual Wake: schedule held off until this ms epoch (0 = none)
let asleep = false;      // live screen state from the server (manual overrides + schedule); drives the Sleep/Wake button
let runningCommit = null; // the commit this player reports — used to detect the restart
let updateNeedsReboot = false; // the offered update touches the kiosk display → frame reboot needed (HANDOFF §15)
let collectionsList = []; // supported connected collections (from /api/collections)
let collectionsBySlug = {}; // slug → collection, for connected card subtitles
let cxSlug = null; // collection selected in the add-connected modal
let cxResolved = null; // last previewed { tokenId, title, image }
let foldersData = { source: 'library', folders: [], root: '' }; // Folder Collections + active source (HANDOFF §17)
let deviceIsFrame = false; // /api/system.role === 'frame' (§17 Phase B): drives the frame-only Folder cache card
let fpPathCur = null; // the folder the picker is currently viewing

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
  el.dataset.id = item.id; // so the single-upload nicety can find this card after a refresh
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
  // Uploads can carry an owner-set title/artist (HANDOFF §7): show the custom title when set (else the
  // filename), and the artist name when set (else the file size), matching how connected pieces show theirs.
  const titleText = !connected && item.title ? item.title : item.original_name;
  const sub = connected
    ? escapeHtml(artistName)
    : (item.artist ? escapeHtml(item.artist) : fmtBytes(item.bytes));
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
      <span class="name" title="${escapeHtml(item.original_name)}">${escapeHtml(titleText)}</span>
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
  // Uploaded pieces: the whole name/artist block is the tap target to edit the title + artist in place
  // (HANDOFF §7). Connected pieces carry their title/artist from the chain/registry, so they aren't editable.
  if (!connected) {
    const metaEl = el.querySelector('.meta');
    metaEl.classList.add('editable');
    metaEl.setAttribute('role', 'button');
    metaEl.setAttribute('tabindex', '0');
    // Enter edit mode on tap / Enter / Space — but NOT once editing: clicks and keystrokes inside the
    // fields bubble up to this same block, so without the guard, clicking the artist field (or typing a
    // space) would re-trigger this and bounce focus back to the title / swallow the keystroke.
    metaEl.addEventListener('click', () => { if (!metaEl.classList.contains('editing')) enterEditMeta(el, item); });
    metaEl.addEventListener('keydown', (e) => {
      if (metaEl.classList.contains('editing')) return;
      if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); enterEditMeta(el, item); }
    });
  }
  return el;
}

// Inline edit of an uploaded piece's title + artist (HANDOFF §7). Swaps the name/artist block for two
// inputs and the actions row for Save/Cancel, in place on the card. Save persists via PATCH then refreshes;
// Cancel (or Esc) re-renders from server state, discarding the edit; Enter saves. Blank clears the field.
function enterEditMeta(cardEl, item) {
  const meta = cardEl.querySelector('.meta');
  const actions = cardEl.querySelector('.actions');
  // Prefill the title with the custom title when set, else the filename, so it is a reminder you can type
  // over (titleInput.select() below highlights it) or arrow through. Clearing it back to blank still reverts
  // to the filename on save (setLibraryMeta stores blank as NULL), so the filename is a default, not forced.
  const curTitle = item.title && item.title.trim() ? item.title : item.original_name;
  const curArtist = item.artist ? item.artist : '';
  meta.classList.remove('editable');
  meta.classList.add('editing');
  meta.removeAttribute('role');
  meta.removeAttribute('tabindex');
  meta.innerHTML = `
    <input class="meta-input meta-title" type="text" maxlength="200" aria-label="Title"
      placeholder="${escapeHtml(item.original_name)}" value="${escapeHtml(curTitle)}">
    <input class="meta-input meta-artist" type="text" maxlength="200" aria-label="Artist"
      placeholder="Artist (optional)" value="${escapeHtml(curArtist)}">`;
  actions.innerHTML = '<button class="meta-cancel">Cancel</button><button class="meta-save">Save</button>';
  const titleInput = meta.querySelector('.meta-title');
  const artistInput = meta.querySelector('.meta-artist');
  const save = async () => {
    await fetch(`/api/library/${item.id}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title: titleInput.value, artist: artistInput.value }),
    });
    await refresh();
  };
  actions.querySelector('.meta-save').addEventListener('click', save);
  actions.querySelector('.meta-cancel').addEventListener('click', () => refresh());
  meta.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); save(); }
    else if (e.key === 'Escape') { e.preventDefault(); refresh(); }
  });
  titleInput.focus();
  titleInput.select();
}

async function loadLibrary() {
  const items = await fetch('/api/library').then((r) => r.json());
  // The tab count is the whole Library (how much art you have), not the filtered view.
  libCount.textContent = items.length ? String(items.length) : '';
  // "Show: In rotation" hides the not-in-rotation pieces from the grid. A view filter only — nothing is
  // deleted, and the server has already ordered the list (sample anchored last) before we narrow it.
  const shown = libraryFilter === 'rotation' ? items.filter((it) => it.in_rotation) : items;
  grid.replaceChildren(...shown.map(card));
  // Tell an empty Library apart from a filter that's hiding everything, so the prompt isn't misleading.
  emptyEl.textContent = shown.length === 0 && items.length > 0
    ? 'No pieces in the rotation yet. Switch Show to All to add some.'
    : 'Nothing here yet, add some art above.';
  emptyEl.hidden = shown.length > 0;
}

// Library sort: persist the choice (a server setting, so it sticks across reloads and devices until
// changed), then re-fetch the grid in the new order. The server applies the order and keeps the
// install sample anchored to the bottom in every option (HANDOFF §7).
async function setLibrarySort(value) {
  librarySort = value;
  await saveSettings({ librarySort: value });
  await loadLibrary();
}

// Library view filter (All / In rotation): persisted like the sort (a shared server setting, so the view
// holds across reloads and devices), then re-render the grid through the filter. Pure presentation — it
// never changes rotation membership, so a piece reappears the moment Show is set back to All.
async function setLibraryFilter(value) {
  libraryFilter = value;
  await saveSettings({ libraryFilter: value });
  await loadLibrary();
}

// ── Rotation tab ────────────────────────────────────────────────────
function rotRow(item, idx, total) {
  const el = document.createElement('div');
  el.className = 'rot-row';
  el.draggable = true;
  el.dataset.id = item.id;
  const isPinned = item.id === pinnedId;
  const cs = item.kind === 'connected' ? thumbCropScale(item.collection) : 0; // crop the thumbnail to match the cropped display
  // First line: the title, then a small type pill (the file's format, or "Connected") and a Fill pill when
  // the clip center-crops — the format/Connected that used to be the whole second line. Second line: the
  // artist (connected pieces from the collection registry, like the Library card; uploads from the owner-set
  // artist field), shown without a "by " prefix and omitted entirely when there's no artist.
  const connected = item.kind === 'connected';
  const artistName = connected
    ? ((collectionsBySlug[item.collection] || {}).artist || '')
    : (item.artist || '');
  const typePill = connected
    ? '<span class="rot-pill rot-pill-connected">Connected</span>'
    : `<span class="rot-pill">${escapeHtml(item.format)}</span>`; // CSS uppercases it (svg -> SVG)
  const fillPill = item.fit === 'fill' ? '<span class="rot-pill">Fill</span>' : '';
  el.innerHTML = `
    <span class="rot-grip" title="Drag to reorder">${GRIP}</span>
    <span class="rot-num">${idx + 1}</span>
    <span class="rot-thumb fit-${item.fit === 'fill' ? 'fill' : 'fit'}${cs ? ' crop' : ''}">${thumbTag(item)}</span>
    <span class="rot-meta">
      <span class="rot-name">${isPinned ? '<span class="rot-pin" title="Pinned">📌</span>' : ''}<span class="rot-title">${escapeHtml(item.original_name)}</span>${typePill}${fillPill}</span>
      ${artistName ? `<span class="rot-sub">${escapeHtml(artistName)}</span>` : ''}
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
  if (!confirm(`Delete "${item.original_name}" from the Library?\nThis removes the file from OpenObject.`)) return;
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
  const addedItems = res.added || [];
  const skipped = res.skipped || [];
  setStatus(
    `Added ${addedItems.length}.` + (skipped.length ? ` Skipped ${skipped.length} unsupported: ${skipped.join(', ')}` : ''),
    true
  );
  await refresh();
  // Single-file upload: open the new piece straight into title/artist editing, so a one-off nudges you to
  // name it. A multi-file drop adds them silently (no per-file prompt). (HANDOFF §7.)
  if (addedItems.length === 1) {
    const cardEl = grid.querySelector(`.card[data-id="${addedItems[0].id}"]`);
    if (cardEl) { cardEl.scrollIntoView({ block: 'nearest' }); enterEditMeta(cardEl, addedItems[0]); }
  }
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
  librarySort = s.librarySort || 'recent';
  sortSelect.value = librarySort;
  libraryFilter = s.libraryFilter || 'all';
  filterSelect.value = libraryFilter;
  // The Name field edits the raw override (empty = using the per-machine default, shown as placeholder).
  hostNameEl.value = s.hostNameCustom || '';
  hostNameEl.placeholder = s.hostNameDefault || 'OpenObject';
  pinnedId = s.pinnedId;
  sleepRanges = (s.sleepRanges || []).map((r) => ({ start: r.start, end: r.end, days: Array.isArray(r.days) ? r.days.slice() : [] }));
  applySleepState(s);
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

// Header status, off the panel's own clock (the same signal the display flips on): a manual Sleep reads
// "Sleeping now", a manual Wake "Awake until <next sleep>", otherwise the schedule's next boundary in the
// week ("Sleeping until 7:00am" / "Awake until 10:00pm").
function renderSleepStatus() {
  if (manualBlank) { sleepStatus.textContent = 'Sleeping now'; return; }
  if (wakeUntil && wakeUntil > Date.now()) { // manual Wake holding the schedule off until the next window
    const d = new Date(wakeUntil);
    sleepStatus.textContent = 'Awake until ' + fmtMin(d.getHours() * 60 + d.getMinutes());
    return;
  }
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

function applySleepState(s) {
  manualBlank = !!s.manualBlank;
  wakeUntil = s.wakeUntil || 0;
  asleep = !!s.asleep;
}
function renderBlank() {
  blankBtn.setAttribute('aria-pressed', String(asleep)); // amber when the screen is asleep
  blankBtn.textContent = asleep ? 'Wake' : 'Sleep';
  renderSleepStatus();
}
// Sleep/Wake: the button reflects the live state, so a press sends the opposite. The server figures out
// the rest, manual Wake during a sleep window holds the schedule off until the next one (see isAsleep).
async function toggleBlank() {
  blankBtn.disabled = true;
  try {
    const s = await saveSettings({ manualBlank: !asleep }).then((r) => r.json());
    applySleepState(s);
    renderBlank();
  } finally {
    blankBtn.disabled = false;
  }
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
    // Git-pull self-update is the frame's mechanism. A Host that isn't a git checkout (the Mac app,
    // which updates through the app itself) hides the whole card rather than showing a dead one.
    if (updateCard) updateCard.hidden = true;
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

  // Power card, gated by what the HOST (not the browsing device) can do: OS power (Reboot / Shut
  // down) needs the frame; the soft Restart needs a supervisor to relaunch. The Mac app as Host has
  // neither, so those rows hide (and the whole card if nothing applies). Restart on a Mac Host is
  // instead "quit and reopen the app".
  const canPower = !!s.isDevice;      // Reboot / Shut down
  const canRestart = !!s.supervised;  // soft Restart
  const rebootRow = rebootBtn && rebootBtn.closest('.device-row');
  const shutdownRow = shutdownBtn && shutdownBtn.closest('.device-row');
  const restartRow = restartBtn && restartBtn.closest('.device-row');
  if (rebootRow) rebootRow.hidden = !canPower;
  if (shutdownRow) shutdownRow.hidden = !canPower;
  if (restartRow) restartRow.hidden = !canRestart;
  const powerCard = restartBtn && restartBtn.closest('section');
  if (powerCard) powerCard.hidden = !(canPower || canRestart);

  const addrs = (s.addresses || []).map((ip) => {
    // Omit the port for plain http (:80) so the frame shows a clean http://<ip> (HANDOFF §11).
    const url = `http://${ip}${s.port && Number(s.port) !== 80 ? ':' + s.port : ''}`;
    return `<a href="${escapeHtml(url)}" target="_blank" rel="noopener">${escapeHtml(url)}</a>`;
  });
  // mDNS name shown bare (openobject.local), linking to its http:// URL.
  if (s.mdns) addrs.push(`<a href="http://${escapeHtml(s.mdns)}" target="_blank" rel="noopener">${escapeHtml(s.mdns)}</a>`);
  // One address per line under the lead instruction.
  frameAddr.innerHTML = addrs.map((a) => `<span class="reach-addr">${a}</span>`).join('') || '—';
  reachEl.hidden = addrs.length === 0;

  // Only the frame buffers a Mac folder; deviceIsFrame gates the cache-meter refresh (the cache UI
  // now lives inside the Folder Collections card, populated by loadFolders, §17 Phase B).
  deviceIsFrame = s.role === 'frame';

  // Tab title self-identifies by device role, so the frame's panel and this computer's panel are
  // told apart when both are open (same static page, so only JS can distinguish them). Role-based,
  // not URL-based, so a tab reads the same however it was reached (localhost / openobject.local / IP).
  document.title = `OpenObject · Control Panel (${deviceIsFrame ? 'Frame' : 'Local'})`;

  // Always-present version line in About — the one place it shows on a Mac Host, where the Software
  // Update card is hidden (not a git checkout). Just the number, no jargon; the commit fingerprint
  // stays in the Software Update card on the frame.
  if (aboutVersion) {
    if (s.version) { aboutVersion.textContent = `Version ${s.version}`; aboutVersion.hidden = false; }
    else aboutVersion.hidden = true;
  }

  // Help card content follows the device: a frame explains pulling a Mac's folder; a Mac explains
  // defining a folder here (and sending one to a frame). Both blocks live in the DOM; show the right one.
  const helpFrame = document.getElementById('helpFrame');
  const helpStandalone = document.getElementById('helpStandalone');
  if (helpFrame) helpFrame.hidden = !deviceIsFrame;
  if (helpStandalone) helpStandalone.hidden = deviceIsFrame;
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
  // by the library/rotation renderers, so they run first. loadFolders fills the Folder Collections
  // list + current source; renderSource runs LAST (after loadRotation) so folder mode overrides the
  // per-piece rotation list with a read-only summary (HANDOFF §17).
  await Promise.all([loadSettings(), loadCollections(), loadFolders()]);
  await Promise.all([loadLibrary(), loadRotation()]);
  renderSource();
}

// ── Folder Collections (HANDOFF §17) ─────────────────────────────
// Setup lives in Settings (a twin of the Connected Collections card); a folder is made the live
// source in the Rotation tab. Everything about a folder (Name, Artist, Fit, Order) is edited here and
// nowhere else; the Rotation tab only selects it.
// Format a byte count for the Folder cache meter: GB for a real folder, MB/KB for smaller.
function fmtCacheSize(n) {
  n = Number(n) || 0;
  if (n >= 1024 ** 3) return `${(n / 1024 ** 3).toFixed(1)} GB`;
  if (n >= 1024 ** 2) return `${Math.round(n / 1024 ** 2)} MB`;
  if (n >= 1024) return `${Math.round(n / 1024)} KB`;
  return `${n} B`;
}

// Folder cache usage (frame only): how much of the selected Mac folder is buffered locally right now.
async function loadFolderCache() {
  const el = document.getElementById('fcCacheUsage');
  if (!el) return;
  try {
    const u = await fetch('/api/folder-cache').then((r) => r.json());
    el.textContent = u.bytes > 0
      ? `Buffered ${fmtCacheSize(u.bytes)} of ${fmtCacheSize(u.capBytes)}. Cache clears on reboot.`
      : 'Cache currently empty.';
  } catch { /* leave the last value on a transient error */ }
}

async function loadFolders() {
  try { foldersData = await fetch('/api/folders').then((r) => r.json()); }
  catch { foldersData = { source: 'library', folders: [], root: '' }; }
  // The Folder Collections card is present on both roles, but its body differs: a Mac MANAGES local
  // folders; the frame's folders are managed on the Mac, so the card holds the local play cache
  // instead (§17 Phase B). The card itself stays collapsible + collapsed-by-default via wireCollapse.
  const manage = document.getElementById('foldersManage');
  const frameGroup = document.getElementById('foldersFrame');
  if (manage) manage.hidden = !!foldersData.remote;
  if (frameGroup) frameGroup.hidden = !foldersData.remote;
  if (foldersData.remote) { fcCount.textContent = ''; loadFolderCache(); }
  renderFolderCard();
}

function renderFolderCard() {
  if (foldersData.remote) return; // frame: folders are managed on the Mac; this local card stays hidden
  const list = foldersData.folders || [];
  fcCount.textContent = list.length ? `${list.length} folder${list.length === 1 ? '' : 's'}` : '';
  if (!list.length) {
    foldersListEl.innerHTML = '<p class="cc-empty">No folders yet. Choose one below to show it instead of the Library.</p>';
    return;
  }
  foldersListEl.replaceChildren(...list.map((f) => {
    const row = document.createElement('div');
    row.className = 'cc-row';
    const fitOpts = [['fit', 'Fit'], ['fill', 'Fill']].map(([v, l]) => `<option value="${v}"${f.fit === v ? ' selected' : ''}>${l}</option>`).join('');
    const countText = `${f.count} piece${f.count === 1 ? '' : 's'}`;
    const artistPart = f.artist ? escapeHtml(f.artist) + ' · ' : '';
    // Display: title, then the artist ONLY when set (no placeholder). The piece count doubles as the
    // "open this folder in Finder" link (in place of showing the path); unreachable shows plain text.
    const sub = f.reachable
      ? `${artistPart}<button type="button" class="fc-open" title="Open this folder">${countText}</button>`
      : `${artistPart}<span class="fc-unreach">can't be reached</span>`;
    row.innerHTML = `
      <span class="cc-meta fc-meta">
        <span class="cc-name fc-name" title="Rename">${escapeHtml(f.name)}</span>
        <span class="cc-sub">${sub}</span>
      </span>
      <span class="cc-controls">
        <span class="cc-ctrl"><span class="cc-ctrl-label">Fit</span><select class="cc-ctrl-select fc-fit" aria-label="Fit for ${escapeHtml(f.name)}">${fitOpts}</select></span>
      </span>
      <button class="cc-hide fc-remove">Remove</button>`;
    row.querySelector('.fc-fit').addEventListener('change', (e) => patchFolder(f.id, { fit: e.target.value }));
    row.querySelector('.fc-name').addEventListener('click', () => enterFolderEdit(row, f));
    const openBtn = row.querySelector('.fc-open');
    if (openBtn) openBtn.addEventListener('click', () => openFolderInFinder(f.id));
    row.querySelector('.fc-remove').addEventListener('click', () => removeFolder(f));
    return row;
  }));
}

// Reveal a folder in the host's file manager (Finder), the quickest way to see what's inside.
async function openFolderInFinder(id) {
  await fetch(`/api/folders/${id}/open`, { method: 'POST' }).catch(() => {});
}

// Click a folder's name to edit its Name + Artist in place (mirrors the Library card, HANDOFF §7): the
// name/sub swap for a Name input and an "Artist (optional)" input beside it, with Save/Cancel (the Fit
// control tucks away to make room). Save persists via PATCH; Cancel/Esc discards; Enter saves. A
// blank name falls back to the folder's own basename (server-side).
function enterFolderEdit(row, folder) {
  const meta = row.querySelector('.fc-meta');
  const controls = row.querySelector('.cc-controls');
  const removeBtn = row.querySelector('.fc-remove');
  if (controls) controls.hidden = true;   // free the row so the two inputs + Save/Cancel have space
  if (removeBtn) removeBtn.hidden = true;
  meta.classList.add('editing');
  const base = (folder.path || '').split('/').filter(Boolean).pop() || 'Folder';
  meta.innerHTML = `
    <input class="meta-input fc-title" type="text" maxlength="80" aria-label="Folder name" placeholder="${escapeHtml(base)}" value="${escapeHtml(folder.name || '')}">
    <input class="meta-input fc-artist-input" type="text" maxlength="80" aria-label="Artist" placeholder="Artist (optional)" value="${escapeHtml(folder.artist || '')}">
    <span class="fc-edit-actions">
      <button type="button" class="cc-hide fc-edit-cancel">Cancel</button>
      <button type="button" class="cc-hide fc-edit-save">Save</button>
    </span>`;
  const titleInput = meta.querySelector('.fc-title');
  const artistInput = meta.querySelector('.fc-artist-input');
  const save = () => patchFolder(folder.id, { name: titleInput.value, artist: artistInput.value });
  meta.querySelector('.fc-edit-save').addEventListener('click', save);
  meta.querySelector('.fc-edit-cancel').addEventListener('click', () => renderFolderCard());
  meta.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') { e.preventDefault(); save(); }
    else if (e.key === 'Escape') { e.preventDefault(); renderFolderCard(); }
  });
  titleInput.focus();
  titleInput.select();
}

async function patchFolder(id, patch) {
  await fetch(`/api/folders/${id}`, { method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(patch) });
  await refresh(); // re-render the card + the Rotation summary if this is the live folder
}

async function removeFolder(f) {
  if (!confirm(`Remove the Folder Collection "${f.name}"? Your files are not touched.`)) return;
  await fetch(`/api/folders/${f.id}`, { method: 'DELETE' });
  await refresh();
}

// Frame-only: while no Mac has been discovered yet, show a brief "Looking for your Mac…" cue (like a
// device picker) before settling into the actionable "app must be open" hint (§17 Phase B).
const MAC_SEARCH_GRACE_MS = 12000;
let macSearchStartedAt = 0;
let macSearchTimer = null;

// A one-click way back to the Library, shown in every "Mac unreachable" panel so the frame is never
// stranded on a folder whose Mac has gone away (§17). It matters most in error state 1, where the
// folder has dropped out of the Source dropdown entirely, leaving no other way to switch off it.
function switchToLibraryButton() {
  return '<button type="button" class="update-btn fs-to-library" id="fsToLibrary">Switch to Library</button>';
}
function wireSwitchToLibrary() {
  const btn = document.getElementById('fsToLibrary');
  if (btn) btn.addEventListener('click', async () => { await saveSettings({ displaySource: 'library' }); await refresh(); });
}

// Rotation tab: the Source dropdown (Library / each saved folder) + folder-mode visibility. Called at
// the end of refresh(), after loadRotation, so folder mode overrides the per-piece list (HANDOFF §17).
function renderSource() {
  const list = foldersData.folders || [];
  const source = foldersData.source || 'library';
  // Library first, a divider, then the saved folders sorted by name (dropdown only — the Settings list
  // keeps its own order). An <hr> in a <select> draws a separator on modern browsers and is ignored on
  // older ones, so it degrades cleanly.
  const byName = [...list].sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
  const opts = ['<option value="library">Library</option>'];
  if (byName.length) opts.push('<hr>');
  for (const f of byName) opts.push(`<option value="${f.id}">${escapeHtml(f.name)}${f.reachable && f.count ? ` · ${f.count} piece${f.count === 1 ? '' : 's'}` : ''}</option>`);
  sourceSelect.innerHTML = opts.join('');
  const active = source !== 'library' ? list.find((f) => String(f.id) === String(source)) : null;
  sourceSelect.value = active ? String(active.id) : 'library';
  sourceSelect.classList.toggle('offline', !!(active && !active.reachable)); // grey a selected folder whose Mac is offline
  // Frame with no Mac sharing folders (§17 Phase B, error state 1): while discovery is still warming up
  // show a brief "Looking for your Mac…" cue (like a device picker), then settle into the actionable hint
  // if none turns up. The empty-list poll keeps running (below), so a Mac that appears mid-search folds in
  // on its own. Only in remote mode; a standalone Host never shows any of this.
  const sourceHint = document.getElementById('sourceHint');
  if (sourceHint) {
    const noMac = !!foldersData.remote && list.length === 0;
    clearTimeout(macSearchTimer);
    if (!noMac) {
      macSearchStartedAt = 0;
      sourceHint.hidden = true;
      sourceHint.textContent = '';
    } else if (foldersData.outdatedMac) {
      // A Mac is on the LAN but running an OpenObject too old for what the frame needs (§17): nudge an
      // update rather than the "app must be open" hint. Generic wording, reused by any future feature.
      macSearchStartedAt = 0;
      sourceHint.hidden = false;
      sourceHint.textContent = 'A newer version of OpenObject is available for your Mac. Please update the app.';
    } else {
      if (macSearchStartedAt === 0) macSearchStartedAt = Date.now();
      const elapsed = Date.now() - macSearchStartedAt;
      sourceHint.hidden = false;
      if (elapsed < MAC_SEARCH_GRACE_MS) {
        sourceHint.textContent = 'Looking for your Mac…';
        macSearchTimer = setTimeout(renderSource, MAC_SEARCH_GRACE_MS - elapsed + 50);
      } else {
        sourceHint.textContent = 'To display a Folder Collection, the OpenObject app must be open on your Mac.';
      }
    }
  }
  // Frame: a remote folder is selected but unreachable AND we have no last-known details for it (rare;
  // the server normally supplies the folder greyed via the list above, §17 error state 2). Fallback:
  // flag it without a name rather than silently reverting to Library.
  if (!!foldersData.remote && source !== 'library' && !active) {
    if (sourceHint) sourceHint.hidden = true;
    orderGroup.hidden = true; rotList.hidden = true; rotEmpty.hidden = true;
    rotCount.textContent = '';
    folderSummary.hidden = false;
    folderSummary.classList.add('fs-offline', 'fs-unreachable');
    folderSummary.innerHTML = '<div class="fs-facts fs-facts-offline">Mac unreachable. Make sure it is awake and the OpenObject app is open.</div>' + switchToLibraryButton();
    wireSwitchToLibrary();
    return;
  }
  const inFolder = !!active;
  orderGroup.hidden = false;   // Order (Sequence/Shuffle) applies to folders too now, like the duration (§17)
  rotList.hidden = inFolder;
  folderSummary.hidden = !inFolder;
  if (inFolder) {
    rotEmpty.hidden = true;
    rotCount.textContent = active.reachable && active.count ? String(active.count) : '';
    renderFolderSummary(active);
  }
}

function renderFolderSummary(f) {
  const fillPill = f.fit === 'fill' ? '<span class="rot-pill">Fill</span>' : ''; // mirror the Library FILL pill (Fit = default, unmarked)
  const sub = f.artist ? `<span class="fs-sub">${escapeHtml(f.artist)}</span>` : '';
  // On the frame a folder is managed on the Mac, so its name is plain text (no jump to a local Settings
  // card) with a tooltip naming the Mac; on a standalone Host it links to Settings. When that Mac is
  // unreachable the folder is greyed (offline) and the facts line becomes the unreachable message.
  const remote = !!foldersData.remote;
  const offline = remote && !f.reachable;
  const facts = offline
    ? 'Mac unreachable. Make sure it is awake and the OpenObject app is open.'
    : f.reachable
      ? `${f.count} piece${f.count === 1 ? '' : 's'}`
      : "Can't be reached";
  const nameEl = remote
    ? `<span class="fs-name fs-name-static"${f.host ? ` title="Shared by ${escapeHtml(f.host)}"` : ''}>${escapeHtml(f.name)}</span>`
    : `<button type="button" class="fs-name" id="fsName" title="Manage in Settings">${escapeHtml(f.name)}</button>`;
  folderSummary.classList.toggle('fs-offline', offline);
  folderSummary.classList.toggle('fs-unreachable', offline);
  folderSummary.innerHTML = `
    <div class="fs-head">${nameEl}${sub}<span class="fs-pill">Folder</span>${fillPill}</div>
    <div class="fs-facts${offline ? ' fs-facts-offline' : f.reachable ? '' : ' fs-facts-warn'}">${facts}</div>${offline ? switchToLibraryButton() : ''}`;
  if (!remote) document.getElementById('fsName').addEventListener('click', gotoFolderSettings);
  if (offline) wireSwitchToLibrary();
}

// The folder name in the Rotation summary jumps to its setup in Settings (expanding the card).
function gotoFolderSettings() {
  switchTab('settings');
  const toggle = document.getElementById('foldersToggle');
  if (toggle.getAttribute('aria-expanded') === 'false') toggle.click(); // expand if collapsed
  document.getElementById('foldersCard').scrollIntoView({ behavior: 'smooth', block: 'start' });
}

// ── Folder picker (server-side subfolder browser) ────────────────
async function openPicker() {
  fpShowMsg('');
  await fpBrowse(null); // start at the sandbox root
  fpOverlay.hidden = false;
}
function closePicker() { fpOverlay.hidden = true; }
function fpShowMsg(t) { fpMsg.textContent = t || ''; fpMsg.hidden = !t; }

async function fpBrowse(p) {
  let view;
  try { view = await fetch('/api/folders/browse' + (p ? '?path=' + encodeURIComponent(p) : '')).then((r) => r.json()); }
  catch { return fpShowMsg('Could not read that folder.'); }
  if (view.error) return fpShowMsg(view.error);
  fpShowMsg('');
  fpPathCur = view.path;
  fpPath.textContent = view.path;
  const rows = [];
  if (view.parent) rows.push({ up: true, path: view.parent });
  for (const d of view.dirs) rows.push({ name: d, path: view.path.replace(/\/+$/, '') + '/' + d });
  if (!rows.length) {
    fpList.innerHTML = '<p class="fp-none">No subfolders here.</p>';
  } else {
    fpList.replaceChildren(...rows.map((r) => {
      const el = document.createElement('button');
      el.type = 'button';
      el.className = 'fp-item' + (r.up ? ' fp-up' : '');
      el.textContent = r.up ? '⬑  Up a level' : '📁  ' + r.name;
      el.addEventListener('click', () => fpBrowse(r.path));
      return el;
    }));
  }
  fpCurrent.textContent = view.mediaCount
    ? `This folder has ${view.mediaCount} compatible file${view.mediaCount === 1 ? '' : 's'}.`
    : 'No compatible files directly in this folder yet.';
  fpUse.disabled = !!view.atRoot; // don't add the whole root; navigate into a folder first
}

async function usePickedFolder() {
  if (!fpPathCur) return;
  const r = await fetch('/api/folders', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ path: fpPathCur }) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) return fpShowMsg(j.error || 'Could not add that folder.');
  closePicker();
  await refresh();
}

// "Choose folder…" uses the host's NATIVE file dialog (HANDOFF §17): on macOS the Finder chooser pops
// on the machine running the player and can navigate the whole Mac. Non-macOS falls back to the small
// in-browser browser (openPicker). The request blocks while the dialog is open, so disable the button.
async function chooseFolder() {
  fcAddBtn.disabled = true;
  try {
    const r = await fetch('/api/folders/pick', { method: 'POST' });
    const j = await r.json().catch(() => ({}));
    if (j.unsupported) return openPicker();  // no native dialog here → in-browser browser
    if (j.remote) return showFolderPickHint(); // opened from another device — the chooser opens on the host
    if (j.cancelled) return;                 // user dismissed the dialog
    if (r.status === 409) return;            // already added — it's already in the list
    if (!r.ok) return alert(j.error || 'Could not add that folder.');
    await refresh();
  } finally {
    fcAddBtn.disabled = false;
  }
}

// Opened from another device (a phone, another computer): the native chooser opens on the host, so
// show a brief note on attempt (never a standing "not supported" banner). It clears itself.
let fcHintTimer;
function showFolderPickHint() {
  fcHint.textContent = 'Folders are added from the computer running OpenObject. Open this page there to choose one.';
  fcHint.hidden = false;
  clearTimeout(fcHintTimer);
  fcHintTimer = setTimeout(() => { fcHint.hidden = true; }, 9000);
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
  renderPicker();                           // no collection pre-selected: the owner picks one first
  cxOverlay.hidden = false;
}
const closeConnected = () => { cxOverlay.hidden = true; };

function renderPicker() {
  const visible = collectionsList.filter((c) => !c.hidden);
  if (!visible.length) {
    cxCollections.innerHTML = '<p class="cc-empty">No collections available — unhide one in Settings.</p>';
    cxAdd.disabled = true;
    return;
  }
  if (cxSlug && !visible.some((c) => c.slug === cxSlug)) cxSlug = null; // no default; the owner must pick a collection
  cxCollections.replaceChildren(...visible.map((c) => {
    const row = document.createElement('div');
    row.className = 'cx-col' + (c.slug === cxSlug ? ' sel' : '');
    row.innerHTML = `
      <span class="cx-col-text">
        <span class="cx-col-art">${escapeHtml(c.name)}</span>
        <span class="cx-col-sub">${escapeHtml(c.artist)}</span>
      </span>
      <span class="cx-col-check">✓</span>`;
    row.addEventListener('click', () => { cxSlug = c.slug; resetResolve(); renderPicker(); maybeAutoPreview(); if (!cxToken.hidden) cxToken.focus(); });
    return row;
  }));
  syncTokenInput();
}

// Small info glyph for the "Supported Token IDs" hint (recolored via CSS, like the other panel icons).
const INFO_ICON = '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"></circle><path d="M12 16v-4"></path><path d="M12 8h.01"></path></svg>';

// A fixedToken collection supports a single piece, so the Token ID field is hidden and the piece is
// resolved automatically; every other collection shows the field and waits for a Token ID.
function syncTokenInput() {
  // No collection picked yet (the owner must choose one first): nothing to enter, so hide the Token ID
  // field and the supported-IDs hint until a selection exists.
  if (!cxSlug) { cxTokenLabel.hidden = true; cxToken.hidden = true; cxSupported.hidden = true; return; }
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
  libView.hidden = name !== 'library'; // the Show/Sort controls only apply to the Library grid
}
Object.keys(TABS).forEach((name) => TABS[name][0].addEventListener('click', () => switchTab(name)));

// ── Wiring ──────────────────────────────────────────────────────────
durDown.addEventListener('click', () => { durationEl.value = Math.max(1, (Number(durationEl.value) || 1) - 1); pushDuration(); });
durUp.addEventListener('click', () => { durationEl.value = (Number(durationEl.value) || 0) + 1; pushDuration(); });
durationEl.addEventListener('change', pushDuration);
// Save the Host name on blur/enter (conventional), then reload so the field reflects the stored
// value (e.g. cleared back to the default). Trimming/length are enforced server-side.
hostNameEl.addEventListener('change', () => { saveSettings({ hostName: hostNameEl.value }).then(() => loadSettings()); });

unitSeg.querySelectorAll('button').forEach((b) =>
  b.addEventListener('click', () => { durationUnit = b.dataset.unit; setSeg(unitSeg, 'unit', durationUnit); pushDuration(); })
);
modeSeg.querySelectorAll('button').forEach((b) =>
  b.addEventListener('click', () => { mode = b.dataset.mode; setSeg(modeSeg, 'mode', mode); saveSettings({ mode }); loadRotation(); })
);

// Folder Collections (HANDOFF §17): switch the Display Source, and the folder picker.
sourceSelect.addEventListener('change', async () => { await saveSettings({ displaySource: sourceSelect.value }); await refresh(); });
fcAddBtn.addEventListener('click', chooseFolder);
fpClose.addEventListener('click', closePicker);
fpCancel.addEventListener('click', closePicker);
fpUse.addEventListener('click', usePickedFolder);
fpOverlay.addEventListener('click', (e) => { if (e.target === fpOverlay) closePicker(); });
window.addEventListener('keydown', (e) => { if (!fpOverlay.hidden && e.key === 'Escape') { e.preventDefault(); closePicker(); } });
sortSelect.addEventListener('change', () => setLibrarySort(sortSelect.value));
filterSelect.addEventListener('change', () => setLibraryFilter(filterSelect.value));
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
wireCollapse('foldersCard', 'foldersToggle');
wireCollapse('wifiCard', 'wifiToggle');
wireCollapse('powerCard', 'powerToggle');
wireCollapse('helpCard', 'helpToggle');

// Keep the Sleep Schedule status line and the week strip's "now" marker current as time passes.
setInterval(() => { if (!panelSettings.hidden) { renderSleepStatus(); renderStrip(); } }, 60000);

// Keep the Folder Collections counts current as files are added/removed on disk (the display already
// re-scans on its own 5s poll; this keeps the control panel's counts in step). Skipped while a folder
// row is being edited or the Source dropdown is focused, so a live re-render never interrupts you.
setInterval(async () => {
  if (deviceIsFrame) loadFolderCache(); // keep the frame's cache meter current as the buffer fills
  // The frame keeps polling even when empty so a just-shared Mac folder appears on its own (§17 #2); a
  // standalone Host has nothing to auto-discover, so it still short-circuits.
  if (!deviceIsFrame && !(foldersData.folders && foldersData.folders.length)) return;
  const a = document.activeElement;
  if (a && (foldersListEl.contains(a) || a === sourceSelect)) return; // mid-interaction — leave it be
  await loadFolders(); // refreshes the card + its count
  renderSource();       // refreshes the Source dropdown counts + the Rotation summary
}, 10000);

checkUpdateBtn.addEventListener('click', checkUpdate);
document.getElementById('fcCacheClearBtn')?.addEventListener('click', async () => {
  await fetch('/api/folder-cache/clear', { method: 'POST' }).catch(() => {});
  loadFolderCache();
});
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

// Connected artwork: entry button → modal. The Token ID resolves on its own a short moment after you stop
// typing (debounced) — there's no key to press; editing the number clears the previous result right away,
// and Enter resolves immediately rather than waiting.
addConnectedBtn.addEventListener('click', openConnected);
cxClose.addEventListener('click', closeConnected);
cxCancel.addEventListener('click', closeConnected);
cxOverlay.addEventListener('click', (e) => { if (e.target === cxOverlay) closeConnected(); });
let cxLookupTimer;
cxToken.addEventListener('input', () => {
  resetResolve();                               // drop any stale preview/enabled Add the instant the number changes
  clearTimeout(cxLookupTimer);
  cxLookupTimer = setTimeout(previewToken, 500);
});
cxToken.addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); clearTimeout(cxLookupTimer); previewToken(); } });
cxAdd.addEventListener('click', addConnected);
ccUnhideAll.addEventListener('click', unhideAll);

// While the Add-connected dialog is open, keep keyboard focus inside it: Tab/Shift+Tab wrap around the
// dialog's own controls instead of walking off the page (and, in Safari, on into the toolbar, which pops
// the Favorites view). Esc closes it, matching the in-place title/artist editor.
window.addEventListener('keydown', (e) => {
  if (cxOverlay.hidden) return;
  if (e.key === 'Escape') { e.preventDefault(); closeConnected(); return; }
  if (e.key !== 'Tab') return;
  const items = [...cxBox.querySelectorAll('button, input')].filter((el) => !el.disabled && !el.hidden);
  if (!items.length) return;
  const first = items[0], last = items[items.length - 1], a = document.activeElement;
  if (!cxBox.contains(a)) { e.preventDefault(); first.focus(); }
  else if (e.shiftKey && a === first) { e.preventDefault(); last.focus(); }
  else if (!e.shiftKey && a === last) { e.preventDefault(); first.focus(); }
});

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
  if (!confirm('Turn off the password? Anyone on your network will be able to make changes again.')) return;
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

'use strict';

// OpenObject control panel — upload, Library, Rotation curation, rotation settings.
// Two tabs: Library (everything uploaded) and Rotation (the curated, ordered subset on
// the panel). Sleep hours, restart/shutdown stubs, and self-update land here next.

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
const panelLibrary = document.getElementById('panelLibrary');
const panelRotation = document.getElementById('panelRotation');
const rotList = document.getElementById('rotList');
const rotCount = document.getElementById('rotCount');
const rotEmpty = document.getElementById('rotEmpty');
const rotHint = document.getElementById('rotHint');

const UNIT_MS = { seconds: 1000, minutes: 60000, hours: 3600000 };

// Inline icons (no webfont dependency — the frame runs offline).
const GRIP = '<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor" aria-hidden="true"><circle cx="5" cy="4" r="1.3"/><circle cx="11" cy="4" r="1.3"/><circle cx="5" cy="8" r="1.3"/><circle cx="11" cy="8" r="1.3"/><circle cx="5" cy="12" r="1.3"/><circle cx="11" cy="12" r="1.3"/></svg>';
const CHEV_UP = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 15l6-6 6 6"/></svg>';
const CHEV_DOWN = '<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9l6 6 6-6"/></svg>';
const X_MARK = '<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 6l12 12M18 6L6 18"/></svg>';

let pinnedId = null;
let mode = 'sequence';
let durationUnit = 'seconds';
let rotationItems = []; // last-loaded Rotation, in order — drives the ↑/↓ moves

const fmtBytes = (n) => {
  if (n < 1024) return n + ' B';
  if (n < 1024 ** 2) return (n / 1024).toFixed(0) + ' KB';
  if (n < 1024 ** 3) return (n / 1024 ** 2).toFixed(1) + ' MB';
  return (n / 1024 ** 3).toFixed(2) + ' GB';
};

function setStatus(msg, sticky) {
  statusEl.textContent = msg || '';
  statusEl.hidden = !msg;
  statusEl.classList.toggle('show', !!sticky);
}

const mediaTag = (item) =>
  item.kind === 'video'
    ? `<video src="/uploads/${item.filename}" muted playsinline preload="metadata"></video>`
    : `<img src="/uploads/${item.filename}" alt="" loading="lazy">`;

// ── Library tab ─────────────────────────────────────────────────────
function card(item) {
  const el = document.createElement('div');
  el.className = 'card';
  const isFill = item.fit === 'fill';
  const isPinned = item.id === pinnedId;
  const inRot = !!item.in_rotation;
  el.innerHTML = `
    <div class="thumb fit-${isFill ? 'fill' : 'fit'}">
      ${mediaTag(item)}
      <span class="badge">${item.format}</span>
      <button class="rot-toggle${inRot ? ' on' : ''}" aria-pressed="${inRot}"
        aria-label="${inRot ? 'Remove from rotation' : 'Add to rotation'}"
        title="${inRot ? 'In the rotation — click to remove' : 'Add to the rotation'}">${inRot ? '✓' : '+'}</button>
      ${isPinned ? '<span class="pin-badge">📌 Pinned</span>' : ''}
    </div>
    <div class="meta">
      <span class="name" title="${item.original_name}">${item.original_name}</span>
      <span class="sub">${fmtBytes(item.bytes)}</span>
    </div>
    <div class="actions">
      <button class="pin" aria-pressed="${isPinned}" title="Hold this piece on the panel permanently">${isPinned ? 'Pinned' : 'Pin'}</button>
      <button class="fit" aria-pressed="${isFill}" title="How this piece fills the square">${isFill ? 'Fill' : 'Fit'}</button>
      <button class="del">Delete</button>
    </div>`;
  el.querySelector('.rot-toggle').addEventListener('click', () => toggleRotation(item));
  el.querySelector('.pin').addEventListener('click', () => togglePin(item));
  el.querySelector('.fit').addEventListener('click', () => toggleFit(item));
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
  el.innerHTML = `
    <span class="rot-grip" title="Drag to reorder">${GRIP}</span>
    <span class="rot-num">${idx + 1}</span>
    <span class="rot-thumb fit-${item.fit === 'fill' ? 'fill' : 'fit'}">${mediaTag(item)}</span>
    <span class="rot-meta">
      <span class="rot-name">${isPinned ? '<span class="rot-pin" title="Pinned">📌</span> ' : ''}${item.original_name}</span>
      <span class="rot-sub">${item.format}${item.fit === 'fill' ? ' · fill' : ''}</span>
    </span>
    <span class="rot-btns">
      <button class="up" ${idx === 0 ? 'disabled' : ''} aria-label="Move earlier">${CHEV_UP}</button>
      <button class="down" ${idx === total - 1 ? 'disabled' : ''} aria-label="Move later">${CHEV_DOWN}</button>
      <button class="rm" aria-label="Remove from rotation" title="Remove from rotation">${X_MARK}</button>
    </span>`;
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
  const res = await fetch('/api/upload', { method: 'POST', body: form }).then((r) => r.json());
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

// loadSettings first (it sets pinnedId/mode the renderers read), then the two lists.
async function refresh() {
  await loadSettings();
  await Promise.all([loadLibrary(), loadRotation()]);
}

// ── Tabs ────────────────────────────────────────────────────────────
function switchTab(name) {
  const lib = name === 'library';
  tabLibrary.setAttribute('aria-selected', String(lib));
  tabRotation.setAttribute('aria-selected', String(!lib));
  panelLibrary.hidden = !lib;
  panelRotation.hidden = lib;
}
tabLibrary.addEventListener('click', () => switchTab('library'));
tabRotation.addEventListener('click', () => switchTab('rotation'));

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

refresh();

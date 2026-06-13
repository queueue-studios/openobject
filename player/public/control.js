'use strict';

// OpenObject control panel — upload, Library, Rotation curation, rotation settings.
// Three tabs: Library (everything uploaded), Rotation (the curated, ordered subset on the
// panel), and Settings (sleep hours + software self-update). Restart/shutdown stubs land next.

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
const sleepRangesEl = document.getElementById('sleepRanges');
const sleepStatus = document.getElementById('sleepStatus');

const updVersion = document.getElementById('updVersion');
const checkUpdateBtn = document.getElementById('checkUpdateBtn');
const applyUpdateBtn = document.getElementById('applyUpdateBtn');
const updApply = document.getElementById('updApply');
const dismissUpdateBtn = document.getElementById('dismissUpdateBtn');
const updStatus = document.getElementById('updStatus');

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
let sleepRanges = []; // up to two daily blank windows (HANDOFF §13)
let manualBlank = false; // instant "Blank panel" override
let runningCommit = null; // the commit this player reports — used to detect the restart

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
  sleepRanges = (s.sleepRanges || []).map((r) => ({ enabled: !!r.enabled, start: r.start, end: r.end }));
  manualBlank = !!s.manualBlank;
  renderSleep();
  renderBlank();
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

// ── Sleep hours (HANDOFF §13) — up to two daily blank windows, shown on a 12h clock ──
const pad2 = (n) => String(n).padStart(2, '0');
const clampInt = (v, lo, hi) => Math.min(hi, Math.max(lo, Math.round(Number(v) || lo)));
const toMin = (hhmm) => { const [h, m] = hhmm.split(':').map(Number); return h * 60 + m; };
const to24 = (h12, min, ap) => pad2((h12 % 12) + (ap === 'PM' ? 12 : 0)) + ':' + pad2(min);
const from24 = (hhmm) => { const [H, M] = hhmm.split(':').map(Number); return { h12: H % 12 || 12, min: M, ap: H >= 12 ? 'PM' : 'AM' }; };
const fmt12 = (hhmm) => { const t = from24(hhmm); return `${t.h12}:${pad2(t.min)} ${t.ap}`; };
const isOvernight = (r) => toMin(r.start) > toMin(r.end);
const inWin = (nowMin, r) => {
  const s = toMin(r.start), e = toMin(r.end);
  if (s === e) return false;
  return s < e ? nowMin >= s && nowMin < e : nowMin >= s || nowMin < e;
};

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
  el.className = 'sleep-row' + (r.enabled ? '' : ' off');
  el.innerHTML = `
    <button class="sleep-cbx${r.enabled ? ' on' : ''}" aria-pressed="${r.enabled}" aria-label="Enable this sleep time">${r.enabled ? CHECK : ''}</button>
    ${timeBlock('start', r.start)}
    <span class="to">→</span>
    ${timeBlock('end', r.end)}
    <span class="overnight"${isOvernight(r) ? '' : ' hidden'}>overnight</span>`;
  const cbx = el.querySelector('.sleep-cbx');
  cbx.addEventListener('click', () => {
    const on = cbx.getAttribute('aria-pressed') !== 'true';
    cbx.setAttribute('aria-pressed', String(on));
    cbx.classList.toggle('on', on);
    cbx.innerHTML = on ? CHECK : '';
    el.classList.toggle('off', !on);
    commitSleep();
  });
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
  return el;
}

const readTime = (block) =>
  to24(
    clampInt(block.querySelector('.t-h').value, 1, 12),
    clampInt(block.querySelector('.t-m').value, 0, 59),
    block.querySelector('.ampm .on')?.dataset.ap || 'AM'
  );
const readRow = (row) => ({
  enabled: row.querySelector('.sleep-cbx').getAttribute('aria-pressed') === 'true',
  start: readTime(row.querySelector('.time12.start')),
  end: readTime(row.querySelector('.time12.end')),
});

function renderSleep() {
  sleepRangesEl.replaceChildren(...sleepRanges.map(sleepRow));
  renderSleepStatus();
}

async function commitSleep() {
  const rows = [...sleepRangesEl.querySelectorAll('.sleep-row')];
  sleepRanges = rows.map(readRow);
  rows.forEach((row, i) => { row.querySelector('.overnight').hidden = !isOvernight(sleepRanges[i]); });
  renderSleepStatus();
  await saveSettings({ sleepRanges });
}

function renderSleepStatus() {
  if (manualBlank) { sleepStatus.textContent = 'Blanked now'; return; }
  const on = sleepRanges.filter((r) => r.enabled);
  if (!on.length) { sleepStatus.textContent = ''; return; }
  const nowMin = new Date().getHours() * 60 + new Date().getMinutes();
  const active = on.find((r) => inWin(nowMin, r));
  if (active) { sleepStatus.textContent = 'Asleep until ' + fmt12(active.end); return; }
  const next = on.reduce(
    (best, r) => { const d = (toMin(r.start) - nowMin + 1440) % 1440; return d < best.d ? { d, start: r.start } : best; },
    { d: Infinity, start: null }
  );
  sleepStatus.textContent = 'Next sleep at ' + fmt12(next.start);
}

function renderBlank() {
  blankBtn.setAttribute('aria-pressed', String(manualBlank));
  blankBtn.textContent = manualBlank ? 'Blanked' : 'Blank panel';
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
  setUpdStatus(
    `<div class="upd-headline">A newer version is available${when}</div>` +
      (list ? `<div class="upd-whats">What’s in it</div><ul class="upd-list">${list}</ul>` : '') +
      link +
      (s.dirty ? '<div class="upd-warn">Heads-up: local file changes are present on this frame.</div>' : '')
  );
  showApply(true);
}

async function applyUpdate() {
  if (!confirm('Update OpenObject and restart the panel?\nThe display briefly shows the OpenObject screen, then returns on the new version.')) return;
  applyUpdateBtn.disabled = true;
  checkUpdateBtn.disabled = true;
  setUpdStatus('Updating… the panel will briefly show the OpenObject screen.');
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
    return setUpdStatus('Update couldn’t complete: ' + escapeHtml(res.error || 'unknown error') + ' Nothing was changed on the panel.');
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

// Poll /healthz until the player comes back up reporting a different commit (HANDOFF §15).
async function waitForRestart(before) {
  setUpdStatus('Updating… waiting for the panel to come back.');
  const started = Date.now();
  await sleepMs(1200); // let it actually go down first
  while (Date.now() - started < 90000) {
    try {
      const h = await fetch('/healthz', { cache: 'no-store' }).then((r) => r.json());
      if (h && h.ok && h.commit && h.commit !== before) {
        showApply(false);
        checkUpdateBtn.disabled = false;
        setUpdStatus('<span class="upd-ok">✓</span> Updated — you’re now up to date.');
        await refresh();
        await loadUpdate(); // refreshes the version line to the new number · date · commit
        return;
      }
    } catch { /* still down — keep polling */ }
    await sleepMs(1500);
  }
  checkUpdateBtn.disabled = false;
  setUpdStatus('The panel is taking longer than expected. It should return on its own — reload this page in a moment.');
}

// loadSettings first (it sets pinnedId/mode the renderers read), then the two lists.
async function refresh() {
  await loadSettings();
  await Promise.all([loadLibrary(), loadRotation()]);
}

// ── Tabs ────────────────────────────────────────────────────────────
const TABS = {
  library: [tabLibrary, panelLibrary],
  rotation: [tabRotation, panelRotation],
  settings: [tabSettings, panelSettings],
};
function switchTab(name) {
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

checkUpdateBtn.addEventListener('click', checkUpdate);
applyUpdateBtn.addEventListener('click', applyUpdate);
dismissUpdateBtn.addEventListener('click', dismissUpdate);

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
loadUpdate(); // self-update status is independent of the library/rotation refresh

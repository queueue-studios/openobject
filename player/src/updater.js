'use strict';

// Self-update from GitHub (HANDOFF §15).
//
// The player runs as a git checkout of this repo, so "update" = a fast-forward pull of the
// source plus a restart. This module owns ALL the git logic, behind a small API the control
// panel drives (Check for updates → Update & restart). It is the repo's only runtime use of
// GitHub; art never touches the repo (§8).
//
// Everything here is owner-initiated and NEVER in the playback path (§9, §15): a failed
// check or an offline frame leaves the rotation untouched — git is only ever spoken to when
// the owner asks. The whole flow is browser-driven, so it works with zero hardware access.
//
// Hard guarantees (§15):
//   • Fast-forward ONLY — never a force-reset. Local divergence makes the update refuse.
//   • Runtime data is never touched: player/data/ and uploads/ are gitignored, so a pull
//     cannot disturb the library, settings, or art.
//   • One track: the current branch's upstream (origin/main). There is no "stable" lane.
//     Tags / GitHub Releases are a point-in-time publishing concept (the version people cite,
//     the Phase 2 image asset), NOT an update channel, so the frame can never lag a fix behind
//     a release. Keep main always deployable (only vetted commits land there).

const path = require('path');
const fs = require('fs');
const { execFile } = require('node:child_process');

// All git commands run against the repo checkout — the repo ROOT, two levels above this
// file (player/src/ → player/ → repo root), where .git lives. Dependency installs run in
// the player app dir, where its package.json + lockfile live.
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const PLAYER_DIR = path.resolve(__dirname, '..');

const GIT_TIMEOUT_MS = 20000;   // a hung network must never wedge a request (§9 offline-safe)
const NPM_TIMEOUT_MS = 180000;  // a dependency reinstall gets longer

// ── Command runner ──────────────────────────────────────────────────
// Resolves {code, stdout, stderr, …} and NEVER rejects — callers branch on `code` so a
// missing binary or a network timeout is reported, never thrown into the request path.
function run(cmd, args, opts = {}) {
  return new Promise((resolve) => {
    execFile(
      cmd,
      args,
      { cwd: REPO_ROOT, timeout: GIT_TIMEOUT_MS, maxBuffer: 8 * 1024 * 1024, ...opts },
      (err, stdout, stderr) => {
        stdout = (stdout || '').toString().trim();
        stderr = (stderr || '').toString().trim();
        if (!err) return resolve({ code: 0, stdout, stderr });
        if (err.code === 'ENOENT') return resolve({ code: -1, stdout, stderr: `${cmd} not found`, missing: true });
        if (err.killed) return resolve({ code: -1, stdout, stderr: stderr || 'timed out', timedOut: true });
        return resolve({ code: typeof err.code === 'number' ? err.code : 1, stdout, stderr });
      }
    );
  });
}
const git = (...args) => run('git', args);

// ── Local git facts (no network) ────────────────────────────────────
async function isGitCheckout() {
  const r = await git('rev-parse', '--is-inside-work-tree');
  return r.code === 0 && r.stdout === 'true';
}
async function currentCommit() {
  const r = await git('rev-parse', '--short', 'HEAD');
  return r.code === 0 ? r.stdout : null;
}
async function currentBranch() {
  const r = await git('rev-parse', '--abbrev-ref', 'HEAD');
  return r.code === 0 && r.stdout !== 'HEAD' ? r.stdout : null;
}
// Read the version off disk each call so it's correct immediately after a pull, before the
// restart (require() would cache the old value for this process's lifetime).
function appVersion() {
  try {
    return JSON.parse(fs.readFileSync(path.join(PLAYER_DIR, 'package.json'), 'utf8')).version || null;
  } catch {
    return null;
  }
}

// /healthz reports the running commit so the control panel can confirm the version that came
// back up after a restart. Computed once at boot (a fresh process = the new commit) and held.
let cachedCommit = null;
async function refreshCommitCache() {
  cachedCommit = await currentCommit();
  return cachedCommit;
}
const cachedCommitSync = () => cachedCommit;

// ── Comparing to upstream ───────────────────────────────────────────
async function fetchUpstream() {
  return git('fetch', '--prune', 'origin');
}

// The ref to compare/advance to: the current branch's upstream tracking ref (origin/main).
async function resolveTarget() {
  const up = await git('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}');
  if (up.code === 0 && up.stdout) return { ref: up.stdout, name: null };
  const br = await currentBranch();
  return br ? { ref: `origin/${br}`, name: null } : null;
}

// behind = commits on target not in HEAD; ahead = local commits not on target (divergence).
// canFastForward iff HEAD is an ancestor of target and there is something to pull.
async function compare(targetRef) {
  const behind = Number((await git('rev-list', '--count', `HEAD..${targetRef}`)).stdout) || 0;
  const ahead = Number((await git('rev-list', '--count', `${targetRef}..HEAD`)).stdout) || 0;
  const anc = await git('merge-base', '--is-ancestor', 'HEAD', targetRef);
  return { behind, ahead, canFastForward: anc.code === 0 && behind > 0 };
}

// Tracked-file changes only — gitignored runtime data (data/, uploads/) never appears here.
async function isDirty() {
  const r = await git('status', '--porcelain', '--untracked-files=no');
  return r.code === 0 && r.stdout.length > 0;
}

async function incomingSubjects(targetRef, limit = 8) {
  const r = await git('log', '--no-merges', `--max-count=${limit}`, '--pretty=format:%h %s', `HEAD..${targetRef}`);
  if (r.code !== 0 || !r.stdout) return [];
  return r.stdout.split('\n').map((s) => s.trim()).filter(Boolean);
}

async function shortSha(ref) {
  const r = await git('rev-parse', '--short', ref);
  return r.code === 0 ? r.stdout : null;
}

// Committer date of a ref, short ISO (YYYY-MM-DD). The control panel shows this as a friendly
// "build date" — the human-legible signal that an update actually landed (the commit covers the
// rare two-updates-in-a-day case). The panel formats it; we keep the value locale-neutral.
async function commitDate(ref) {
  const r = await git('show', '-s', '--format=%cs', ref);
  return r.code === 0 && r.stdout ? r.stdout.trim() : null;
}

// The repo's web home, derived from the origin remote, so the panel can link "What's new" to the
// exact changes on GitHub. Handles both https and ssh remotes. (The repo is private today, so the
// link only works for accounts with access until it goes public — harmless until then.)
async function repoWebUrl() {
  const r = await git('remote', 'get-url', 'origin');
  if (r.code !== 0 || !r.stdout) return null;
  const url = r.stdout.replace(/\.git$/, '');
  const ssh = url.match(/^git@([^:]+):(.+)$/); // git@github.com:org/repo
  const web = ssh ? `https://${ssh[1]}/${ssh[2]}` : url.replace(/^ssh:\/\//, 'https://');
  return /^https?:\/\//.test(web) ? web : null; // only a real web URL is linkable (skip local-path remotes)
}

// Did the dependency manifest change between two commits? Only then is a reinstall needed.
async function manifestsChanged(a, b) {
  const r = await git('diff', '--name-only', a, b, '--', 'player/package.json', 'player/package-lock.json');
  return r.code === 0 && r.stdout.length > 0;
}

// Files that would change in the working tree if we fast-forwarded to the target.
async function changedFiles(targetRef) {
  const r = await git('diff', '--name-only', `HEAD..${targetRef}`);
  if (r.code !== 0 || !r.stdout) return [];
  return r.stdout.split('\n').map((s) => s.trim()).filter(Boolean);
}

// Does this path run on the frame? Doc/website/meta paths (docs/, site/, README, LICENSE,
// .github, the handoff PDF) are neither served nor executed by the player, so a change confined
// to them is invisible on the frame and must not prompt an "Update & restart." Everything else,
// player/, assets/ (the branding the display serves live from /assets), installer/, and any NEW
// path, counts as a real update: unknown paths default to "real" so a genuine update is never hidden.
function isAppRelevantPath(file) {
  const cosmetic =
    file.startsWith('docs/') ||
    file.startsWith('site/') ||
    file.startsWith('.github/') ||
    file === 'README.md' ||
    file === 'LICENSE' ||
    file === 'CLAUDE.md' ||
    file === '.gitignore' ||
    file === 'OpenObject-HANDOFF.pdf';
  return !cosmetic;
}

// Does this update need a frame REBOOT to fully apply? A self-update restarts the player and the
// control panel reloads itself, but the kiosk Chromium keeps showing the old /display until the
// device reboots. So a change to the display page or its self-playing demo (player/public/display.*
// or arcade.js) or the kiosk launcher (installer/kiosk/) is the reboot-requiring kind; the update
// view surfaces it (HANDOFF §15).
function isKioskFacingPath(file) {
  return /^player\/public\/(display|arcade)\./.test(file) || file.startsWith('installer/kiosk/');
}

// ── Public API ──────────────────────────────────────────────────────

// Instant, no-network status for page load: what we're running. Offline-safe.
async function localStatus() {
  const base = { version: appVersion(), commit: await currentCommit(), branch: await currentBranch() };
  if (!(await isGitCheckout())) return { ...base, isRepo: false, unavailable: 'not-a-git-checkout' };
  return { ...base, isRepo: true, date: await commitDate('HEAD'), repoUrl: await repoWebUrl() };
}

// Check for updates: fetch, then compare HEAD to the upstream target. Network call; a
// failure is reported as `offline` and changes nothing.
async function check() {
  const common = {
    version: appVersion(),
    commit: await currentCommit(),
    branch: await currentBranch(),
    date: await commitDate('HEAD'),
    repoUrl: await repoWebUrl(),
    checkedAt: new Date().toISOString(),
  };
  if (!(await isGitCheckout())) return { ...common, ok: false, unavailable: 'not-a-git-checkout' };

  const f = await fetchUpstream();
  if (f.code !== 0) return { ...common, ok: false, offline: true, detail: f.stderr || 'could not reach GitHub' };

  const target = await resolveTarget();
  if (!target) {
    return { ...common, ok: true, updateAvailable: false, target: null, note: 'no upstream configured' };
  }

  const { behind, ahead, canFastForward } = await compare(target.ref);
  const targetSha = await shortSha(target.ref);

  // Surface only updates the owner can act on: a fast-forward that changes something the frame
  // actually runs. If every incoming file is doc/website/meta (see isAppRelevantPath), the frame
  // is effectively up to date, so report no update rather than nag a pointless restart.
  const files = behind > 0 ? await changedFiles(target.ref) : [];
  const appRelevant = files.some(isAppRelevantPath);
  const updateAvailable = behind > 0 && appRelevant;

  return {
    ...common,
    ok: true,
    target: { ref: target.ref, name: target.name, commit: targetSha, date: await commitDate(target.ref) },
    behind,
    ahead,
    dirty: await isDirty(),
    updateAvailable,
    cosmeticOnly: behind > 0 && !appRelevant,
    canFastForward,
    diverged: ahead > 0,
    // True when the owner must reboot the frame after updating to reload the kiosk display (HANDOFF §15).
    requiresReboot: updateAvailable && files.some(isKioskFacingPath),
    subjects: updateAvailable ? await incomingSubjects(target.ref) : [],
    // Link "What's new" to the exact diff on GitHub (current → target), for the curious.
    compareUrl:
      updateAvailable && common.repoUrl && common.commit && targetSha
        ? `${common.repoUrl}/compare/${common.commit}...${targetSha}`
        : null,
  };
}

// Apply the update: re-validate, fast-forward ONLY, reinstall deps if the manifest changed.
// Returns a result; it does NOT exit — the caller (server) decides whether to restart, so
// this stays pure logic that's easy to test. Refuses (and changes nothing) on divergence.
async function apply() {
  if (!(await isGitCheckout())) return { ok: false, error: 'not a git checkout — update unavailable' };

  const f = await fetchUpstream();
  if (f.code !== 0) return { ok: false, offline: true, error: 'could not reach GitHub' };

  const target = await resolveTarget();
  if (!target) return { ok: false, error: 'no upstream configured' };

  const { behind, canFastForward } = await compare(target.ref);
  if (behind === 0) return { ok: true, updated: false, upToDate: true };
  if (!canFastForward) {
    return {
      ok: false,
      diverged: true,
      error: 'This frame has local changes, so it can’t fast-forward. Update paused to avoid overwriting them.',
    };
  }

  const beforeHead = (await git('rev-parse', 'HEAD')).stdout;

  // Fast-forward ONLY (§15) — never a reset/clean/force. The working tree and the gitignored
  // runtime data are untouched.
  const merge = await git('merge', '--ff-only', target.ref);
  if (merge.code !== 0) {
    return { ok: false, error: 'fast-forward failed: ' + (merge.stderr || 'unknown') };
  }
  const afterHead = (await git('rev-parse', 'HEAD')).stdout;

  // Reinstall dependencies only when the manifest actually changed across the update. Use `npm ci`,
  // not `npm install`: it installs exactly what the lockfile pins and never rewrites it, so the
  // checkout stays clean and a later fast-forward is never blocked by a self-inflicted lockfile edit.
  const depsChanged = await manifestsChanged(beforeHead, afterHead);
  let installed = false;
  let installError = null;
  if (depsChanged) {
    const r = await run('npm', ['ci', '--omit=dev', '--no-audit', '--no-fund'], { cwd: PLAYER_DIR, timeout: NPM_TIMEOUT_MS });
    if (r.code === 0) installed = true;
    else installError = r.stderr || 'npm ci failed';
  }

  return {
    ok: true,
    updated: true,
    fromCommit: beforeHead.slice(0, 7),
    toCommit: await shortSha('HEAD'),
    version: appVersion(),
    depsChanged,
    installed,
    installError,
  };
}

module.exports = {
  isAppRelevantPath,
  isKioskFacingPath,
  localStatus,
  check,
  apply,
  refreshCommitCache,
  cachedCommitSync,
  REPO_ROOT,
  PLAYER_DIR,
};

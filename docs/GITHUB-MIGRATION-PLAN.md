# GitHub + Licensing Migration Plan: personal account to Queueue Studios LLC

> **Document type:** Execution plan. **COMPLETE (2026-07-03).** Kept as a record; can be
> retired. The full narrative also lives in HANDOFF §20 (2026-07-03).
> **Status (updated 2026-07-03):** Org `queueue-studios` created (business-owned by
> `mattonchain`, private membership, display name "Queueue Studios LLC"); repo
> **transferred** to `queueue-studios/openobject`; attribution account `queueue-dev`
> created; local remote re-pointed; LLC commit identity set (name "Queueue Studios LLC",
> email the `queueue-dev` noreply). **Checkpoint 1 (URL rewiring + identity) committed** (`56c775a`); frame remote re-pointed
> on the deployed unit. Decisions locked: **D5 = no history rewrite**, **D6 = all rights
> reserved + narrow run-it grant**, **D7 = copyright → Queueue Studios LLC**. **Checkpoint
> 2 (license + docs) done:** new proprietary `LICENSE`, copyright to the LLC, and the
> "noncommercial" wording swept from README, the control panel About line, `package.json`
> + lockfile, the Mac app copyright string, the homepage status line, CLAUDE.md,
> MAC-APP-PLAN, and a HANDOFF §20 entry. **Checkpoint 3 (homepage) done:** gh-pages
> republished (`5c4f80e`); the transfer had disabled Pages + dropped the custom domain, so
> Pages was re-enabled, the domain re-verified at the **org level** (new
> `_github-pages-challenge-queueue-studios` TXT at GoDaddy), and `openobject.io` re-set as
> the repo custom domain (DNS check green). **openobject.io is live under the org.** Only
> low-priority leftover: the GoDaddy `www` CNAME may still point at `mattonchain.github.io`
> (apex works regardless).
> **Relationship to the spec:** `HANDOFF.md` stays the authoritative engineering
> spec. This file is the migration plan; as pieces land, the relevant HANDOFF
> sections, the Setup Guide, README, and this file are updated in the same change,
> and this file is trimmed or retired when the move is complete.

---

## 1. Why this exists

Everything OpenObject publishes should sit under the LLC (Queueue Studios LLC), with
Matt's personal name, handle, and email kept off the public face. Two separate goals
got bundled into one move:

1. **Move the repo under an LLC GitHub Organization** (public face = the LLC, not a
   person), owned and administered by Matt's real account.
2. **Change the license posture** from PolyForm Noncommercial (source available for
   noncommercial use) to **proprietary, all rights reserved** (source stays public,
   but no license to use, copy, redistribute, or reuse it, beyond a narrow grant to
   run it). This tightens control ahead of paid tvOS and iPad apps.

The Apple side is already done: signing, notarization, and the Developer ID are under
**Queueue Studios LLC** (team `J87JRCN9RM`, Apple ID `developer@queueue.tv`). This
plan brings GitHub and the license into line with that.

## 2. Decisions needed from Matt (the blockers)

Nothing below starts until these are set.

- **D1. Org handle.** Proposed: `queueue` (org display name "Queueue Studios LLC").
  Confirm the handle or pick another. The repo becomes `queueue/openobject`.
- **D2. Owning account.** Matt's existing personal account (`mattonchain`) owns and
  admins the org, with **private org membership** so he is not publicly listed.
  (Settled in discussion; recorded here for the record.)
- **D3. Attribution account.** A second, standard GitHub account for
  `developer@queueue.tv`, used only as the commit-author identity. Confirm we create
  it. Its username is public on commits, so pick a neutral one (for example
  `queueue-dev` or `openobject`), not a personal name.
- **D4. Commit identity strings.** Proposed `user.name = "Queueue Studios"` and
  `user.email =` the attribution account's GitHub `noreply` address (max privacy) or
  `developer@queueue.tv` (a role address, fine to expose). Recommendation: the role
  address, so commits link cleanly to the attribution account.
- **D5. History rewrite: yes or no.** The plain repo **transfer** keeps all existing
  history, which still contains 47 commits with Matt's real Gmail and his `MattLHx`
  or `mattonchain` handle throughout. Options:
  - **No rewrite (default):** smooth transfer, keeps releases, stars, and automatic
    redirects. Old commits keep the personal footprint.
  - **Rewrite:** scrub author and committer identity across all history to the LLC
    identity. Truly clean, but changes every commit SHA, so the frame must re-clone,
    the transfer redirect benefit is lost, and it is a force-push on a public repo.
    Best done now if ever, while adoption is one frame.
- **D6. License terms.** Proprietary, all rights reserved, plus a narrow explicit
  grant to download, install, run, and update the software to operate a display or
  frame for personal noncommercial use. Confirm the narrow-grant wording is wanted
  (recommended) versus pure all-rights-reserved with revival tolerated in practice.
- **D7. Copyright holder.** The LICENSE `Required Notice` currently reads
  "The Museum of Digital Art (@mymoda_io)". Change to **Queueue Studios LLC**? (Very
  likely yes, for consistency with the LLC posture.)

## 3. Scope guard: what is NOT changing

To keep this small (no "too much change at once"):

- **The repo stays public.** No private repo, no sister-repo split. Rejected as
  overhead.
- **dmg releases and frame auto-updates keep working unchanged**, because the repo
  stays public. The self-update URL is derived at runtime from `git remote get-url
  origin` (`player/src/updater.js`), so it follows the new remote automatically once
  the frame's remote is re-pointed.
- **No product or engine behavior changes.** This is accounts, URLs, git identity,
  and license text only.
- **The Mac app plan is untouched** and resumes at Branding afterward.

## 4. The work, by owner

### A. Accounts and org (Matt does; Claude gives exact steps)

Account creation and the repo transfer are outward-facing and account-level, so Matt
performs them. Claude supplies the precise click-path for each.

1. Create the **organization** (Free plan, not Enterprise). Org creation asks for a
   **billing/contact email**; use an LLC address (for example `developer@queueue.tv`).
   That email is private and never enters commits.
2. Set org display name to "Queueue Studios LLC"; set membership visibility to
   **private**.
3. Create the **attribution GitHub account** for `developer@queueue.tv`; verify the
   email; enable "Keep my email addresses private".
4. **Transfer** `mattonchain/openobject` to `queueue/openobject` (Settings, Danger
   Zone, Transfer). GitHub sets up automatic redirects from the old path.

### B. Commit identity (Claude sets in-repo; Matt approves strings)

5. Set a **repo-local** git identity so future commits carry the LLC identity, not
   `MattLHx`:
   `git config user.name "Queueue Studios"` and `git config user.email <D4 choice>`.
6. Optionally add a global **conditional include** so any repo under a chosen folder
   auto-uses this identity, per D4. Documented for Matt to apply on his machine.

### C. In-repo reference updates (Claude edits; one commit)

Replace every `mattonchain/openobject` with `queueue/openobject`. Full checklist in §5.

### D. License and docs terminology (Claude drafts; Matt approves wording)

7. Replace `LICENSE` (PolyForm Noncommercial) with the proprietary terms from D6, with
   the D7 copyright holder and the new repo URL.
8. Retire "source available for noncommercial use" and "Free for noncommercial use"
   everywhere; the new line is roughly "Source is public. All rights reserved. No
   license to use, copy, or redistribute", plus the narrow run-it grant. Update:
   README, `site/index.html` status line, `player/public/control.html` About legal
   line, HANDOFF, the Setup Guide, and `player/package.json` `license` field.
9. Update the memory rule that says to always call it "source available for
   noncommercial use" (that guidance is now retired).

### E. Frame, DNS, and domain (Matt runs on the frame; Claude gives commands)

10. **Re-point the frame's git remote** to the new org URL:
    `sudo git -C /opt/openobject remote set-url origin https://github.com/queueue/openobject.git`
    (exact path per the installer), then a normal Software Update to confirm it pulls.
11. **openobject.io on GitHub Pages:** after transfer, re-check the custom domain and
    HTTPS under the org; the account-level domain verification and the `www` CNAME to
    `mattonchain.github.io` (HANDOFF §DNS) may need re-verification under the org.
    Matt handles GoDaddy DNS; Claude specifies the exact records.

## 5. Blast-radius checklist (files with `mattonchain/openobject`)

Claude edits these in one commit (part C):

- [ ] `LICENSE:2` (repo URL) and `LICENSE:1` (copyright holder, per D7)
- [ ] `docs/HANDOFF.md:6` (repo header) and `:956` (the `www` CNAME note)
- [ ] `docs/MAC-DISPLAY-SETUP.md:27`
- [ ] `site/index.html` lines 14, 19 (og:image, twitter:image raw URLs), 317, 318,
      360, 369, 382, 383
- [ ] `installer/install.sh:28` (`OO_ORIGIN` default)
- [ ] `installer/systemd/openobject-kiosk.service:7`,
      `openobject-player.service:8`, `openobject-netcheck.service:6` (`Documentation=`)
- [ ] `player/public/control.html:208` (Source code link)
- [ ] `docs/MAC-APP-PLAN.md` lines 224, 249, 312 (license phrasing)

Not hardcoded, no edit needed: `player/src/updater.js` `repoWebUrl()` derives the URL
from the git remote, so it follows the new origin automatically.

## 6. Order of operations

Chosen to avoid a window where links point nowhere:

1. Matt: create org, attribution account, set visibility (A1 to A3).
2. Matt: transfer the repo (A4). Redirects keep old links alive.
3. Claude: set commit identity (B5), update all in-repo references and license/docs
   (C, D) in one or two reviewable commits, pushed on Matt's OK.
4. Matt: re-point the frame remote and run a Software Update to confirm (E10).
5. Matt: re-verify Pages custom domain and DNS (E11).
6. Update HANDOFF §20 and this file's status to done; retire this file when clean.

## 7. Rollback and safety

- The transfer is reversible (transfer back) and GitHub keeps redirects, so old clone
  URLs and links keep working during the cutover.
- If D5 is "rewrite," take a full backup clone (`git clone --mirror`) before rewriting,
  and expect the frame to need a fresh clone rather than a pull.
- No credentials or tokens are handled by Claude. Matt performs all account creation,
  the transfer, and any frame or DNS commands; Claude supplies exact steps and runs
  only the in-repo git edits, pushing on explicit approval.

## 8. After this move

Resume the Mac app plan at **Branding** (real OPEN/OBJECT icon and wordmark), then the
Phase C release (`.dmg` + Sparkle), then Phase D docs, all now under the LLC identity
and the new license.

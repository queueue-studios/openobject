#!/usr/bin/env bash
set -euo pipefail

# Bundle the OpenObject engine into the Mac app (MAC-APP-PLAN §B1b; HANDOFF §20, 2026-07-02).
#
# Stages a PINNED Node runtime + a snapshot of player/ into the app bundle's Resources, so the
# signed app is fully self-contained. This is the key difference from the frame: the frame git-pulls
# a mutable checkout, but a notarized .app is sealed, so the engine must ship INSIDE each build
# (MAC-APP-PLAN §4). One engine, no fork: player/ is COPIED here, never duplicated in the repo
# (guardrail, MAC-APP-PLAN §9). The staged payload is gitignored runtime, never committed.
#
# Runs two ways:
#   • As an Xcode build phase — $CONTENTS_FOLDER_PATH is set, so it copies into the built .app.
#   • Standalone (for testing)  — copies into mac-app/Resources/ instead.
#
# Phase C note: for a SIGNED build the nested `node` binary must be codesigned (hardened runtime)
# and this staging must happen BEFORE the codesign step, not after. B1b is unsigned/local, so it
# runs as a post-build copy for now; Phase C re-sequences and signs the nested binary.

NODE_VERSION="24.18.0"          # pinned; Node 24 LTS (Krypton). >=22.5 for node:sqlite, flag-free.
NODE_PLATFORM="darwin-arm64"    # v1 is Apple Silicon only (see project.yml ARCHS)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAC_APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$MAC_APP_DIR/.." && pwd)"
PLAYER_SRC="$REPO_ROOT/player"
CACHE_DIR="$MAC_APP_DIR/.node-cache"

# Destination Resources dir: the built app under Xcode, else mac-app/Resources for standalone test.
if [ -n "${CONTENTS_FOLDER_PATH:-}" ]; then
  DEST="${TARGET_BUILD_DIR}/${CONTENTS_FOLDER_PATH}/Resources"
else
  DEST="$MAC_APP_DIR/Resources"
fi

echo "[bundle-engine] Node v$NODE_VERSION ($NODE_PLATFORM) + player/ → $DEST"
mkdir -p "$DEST" "$CACHE_DIR"

# ── 1. Node binary: download + checksum-verify once, then cache ───────────────
NODE_PKG="node-v${NODE_VERSION}-${NODE_PLATFORM}"
NODE_TGZ="$CACHE_DIR/${NODE_PKG}.tar.gz"
NODE_BIN_CACHED="$CACHE_DIR/${NODE_PKG}-node"
if [ ! -x "$NODE_BIN_CACHED" ]; then
  echo "[bundle-engine] fetching Node…"
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_PKG}.tar.gz" -o "$NODE_TGZ"
  # Verify against the official SHASUMS256.txt before trusting the binary.
  EXPECTED="$(curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" | grep " ${NODE_PKG}.tar.gz\$" | awk '{print $1}')"
  ACTUAL="$(shasum -a 256 "$NODE_TGZ" | awk '{print $1}')"
  if [ -z "$EXPECTED" ] || [ "$EXPECTED" != "$ACTUAL" ]; then
    echo "[bundle-engine] ERROR: Node checksum mismatch (expected '$EXPECTED', got '$ACTUAL')" >&2
    rm -f "$NODE_TGZ"; exit 1
  fi
  tar -xzf "$NODE_TGZ" -C "$CACHE_DIR" "${NODE_PKG}/bin/node"   # just the binary
  cp "$CACHE_DIR/${NODE_PKG}/bin/node" "$NODE_BIN_CACHED"
  rm -rf "$CACHE_DIR/${NODE_PKG}"
  chmod +x "$NODE_BIN_CACHED"
fi
cp "$NODE_BIN_CACHED" "$DEST/node"
chmod +x "$DEST/node"

# ── 2. player/ snapshot: source + pure-JS node_modules; NEVER runtime data ────
echo "[bundle-engine] copying player/…"
rm -rf "$DEST/player"
mkdir -p "$DEST/player"
# Excludes: data/ + uploads/ are runtime (gitignored; must never ship). node_modules IS copied —
# the three deps (express, multer, bonjour-service) are pure JS, so the tree is portable.
rsync -a \
  --exclude 'data/' \
  --exclude 'uploads/' \
  --exclude '.DS_Store' \
  --exclude '.git' \
  "$PLAYER_SRC/" "$DEST/player/"

# Safety net: if the source had no node_modules, install production deps into the staged copy.
if [ ! -d "$DEST/player/node_modules" ]; then
  echo "[bundle-engine] player deps missing — running npm ci in the staged copy…"
  ( cd "$DEST/player" && npm ci --omit=dev )
fi

echo "[bundle-engine] done: node $("$DEST/node" --version) + player/ ($(du -sh "$DEST/player" | awk '{print $1}'))"

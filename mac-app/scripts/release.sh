#!/usr/bin/env bash
set -euo pipefail

# Cut a Mac release (MAC-APP-PLAN §C4): bump the shared version, build, sign, notarize, package the
# dmg, and generate the Sparkle appcast. This runs the LOCAL pipeline only. The outward publish
# (git commit + tag, the GitHub Release, and the gh-pages appcast) is a deliberate separate step,
# printed at the end and driven from chat so it stays gated.
#
# Usage: release.sh <version>            e.g.  release.sh 1.1.0
#
# Run on Matt's Mac (it needs the keychain): the LLC "Developer ID Application" cert, the notary
# profile "openobject-llc", and the Sparkle EdDSA private key (from generate_keys). Safe to re-run.

VERSION="${1:?usage: release.sh <version>   e.g. release.sh 1.1.0}"
MAC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$MAC/.." && pwd)"
cd "$MAC"

TAG="v$VERSION"
GH_REPO="queueue-studios/openobject"
DL_PREFIX="https://github.com/$GH_REPO/releases/download/$TAG/"

# --- 1. bump the shared version (engine + Mac app) --------------------------------------------------
echo "[release] bumping version to $VERSION"
( cd "$REPO_ROOT/player" && npm version "$VERSION" --no-git-tag-version --allow-same-version >/dev/null )
# Mac app: the marketing version, plus an incrementing build number (Sparkle compares CFBundleVersion).
CUR_BUILD="$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml)"
NEW_BUILD=$(( ${CUR_BUILD:-1} + 1 ))
sed -i '' -E "s/MARKETING_VERSION: \"[0-9.]+\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" project.yml
echo "        engine + app → $VERSION (build $NEW_BUILD)"

# --- 2. regenerate the project + build Release (bundles the engine via the post-build script) --------
echo "[release] xcodegen + xcodebuild (Release) ..."
xcodegen generate >/dev/null
xcodebuild -project OpenObject.xcodeproj -scheme OpenObject -configuration Release \
  -derivedDataPath build clean build >/dev/null
APP="$MAC/build/Build/Products/Release/OpenObject.app"
[ -d "$APP" ] || { echo "[release] build failed (no app)"; exit 1; }
SPARKLE_BIN="$MAC/build/SourcePackages/artifacts/sparkle/Sparkle/bin"

# --- 3. sign + notarize + staple the app (Sparkle helpers, node, then the app) -----------------------
echo "[release] sign + notarize + staple the app ..."
"$MAC/scripts/sign-and-notarize.sh" "$APP"

# --- 4. build + sign + notarize + staple the dmg ----------------------------------------------------
DMG="$MAC/build/OpenObject-$VERSION.dmg"
echo "[release] build + notarize the dmg ..."
"$MAC/scripts/build-dmg.sh" "$APP" "$DMG"

# --- 5. Sparkle appcast (signs the dmg with the EdDSA private key from the keychain) -----------------
echo "[release] generate the appcast ..."
UPDATES="$MAC/build/updates"
rm -rf "$UPDATES"; mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"
"$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DL_PREFIX" "$UPDATES"
APPCAST="$UPDATES/appcast.xml"
[ -f "$APPCAST" ] || { echo "[release] appcast not generated"; exit 1; }

cat <<EOF

====================================================================
 Local release artifacts ready for $VERSION
   app     : $APP  (signed, notarized, stapled)
   dmg     : $DMG
   appcast : $APPCAST
====================================================================
 Next (outward, done from chat so it stays gated):
   1. Commit the version bump + tag $TAG.
   2. Create the GitHub Release and upload the dmg (asset name must stay
      OpenObject-$VERSION.dmg so the appcast URL resolves).
   3. Publish appcast.xml to gh-pages (openobject.io/appcast.xml).
 Paste the paths above back into chat and we'll finish the publish.
====================================================================
EOF

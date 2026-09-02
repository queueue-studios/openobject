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

# --- 0. show what is shipping since the last release, so nothing gets missed -------------------------
# The build always comes from HEAD, so the risk is never "missed code", it is "did we notice everything
# that changed" (for the notes, and a sanity check). Print the changelog since the previous tag.
LAST_TAG="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null || true)"
if [ -n "$LAST_TAG" ]; then
  echo "[release] changes since $LAST_TAG (all of this ships in $VERSION; review before continuing):"
  git -C "$REPO_ROOT" log --oneline "$LAST_TAG"..HEAD | sed 's/^/           /'
  echo
fi

# --- 1. bump the version on ALL FOUR surfaces -------------------------------------------------------
# One version line across the platform (Matt, 2026-09-01, "option C"): the engine/frame, the Mac app,
# and BOTH App Store shells move together. The shells used to be bumped by hand and silently drifted a
# version or two behind every cut (they sat at 1.6.2 while the platform was at 1.8.0), which is what
# E19 was raised for. Doing it here makes "the versions are in sync" a property of the tool instead of
# something a human has to remember at the end of a long release.
#
# Build numbers are deliberately NOT shared. CURRENT_PROJECT_VERSION is a per-platform counter and App
# Store Connect rejects a build number it has already seen for that platform, so each surface keeps its
# own and simply increments. They are bumped on every run even when no App Store upload follows: an
# unused build number costs nothing, while a COLLIDING one blocks an upload at the worst possible
# moment, halfway through a release.
bump_app_version() {                      # <app dir> <label>
  local dir="$1" label="$2" cur new
  cur="$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' "$dir/project.yml")"
  new=$(( ${cur:-0} + 1 ))
  sed -i '' -E "s/MARKETING_VERSION: \"[0-9.]+\"/MARKETING_VERSION: \"$VERSION\"/" "$dir/project.yml"
  sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"$new\"/" "$dir/project.yml"
  # The generated .xcodeproj is COMMITTED for these apps, so regenerate it here. Bumping project.yml
  # alone would leave the project that actually builds still carrying the old version.
  ( cd "$dir" && xcodegen generate >/dev/null )
  echo "        $label → $VERSION (build $new)"
}

echo "[release] bumping version to $VERSION on all four surfaces"
( cd "$REPO_ROOT/player" && npm version "$VERSION" --no-git-tag-version --allow-same-version >/dev/null )
echo "        engine + frame → $VERSION"
# Mac app: marketing version plus an incrementing build number (Sparkle compares CFBundleVersion). Its
# xcodegen run happens in step 2, so only the file is touched here.
CUR_BUILD="$(sed -nE 's/.*CURRENT_PROJECT_VERSION: "([0-9]+)".*/\1/p' project.yml)"
NEW_BUILD=$(( ${CUR_BUILD:-1} + 1 ))
sed -i '' -E "s/MARKETING_VERSION: \"[0-9.]+\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
sed -i '' -E "s/CURRENT_PROJECT_VERSION: \"[0-9]+\"/CURRENT_PROJECT_VERSION: \"$NEW_BUILD\"/" project.yml
echo "        Mac app → $VERSION (build $NEW_BUILD)"
bump_app_version "$REPO_ROOT/tv-app"   "tvOS app"
bump_app_version "$REPO_ROOT/ipad-app" "iOS app"

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

# Keep the on-main copy in sync so a future gh-pages re-publish (from site/) can't revert the live feed
# to an older version. It drifted silently before 1.4.0. Commit this together with the version bump.
cp "$APPCAST" "$REPO_ROOT/site/appcast.xml"
echo "        synced → site/appcast.xml"

cat <<EOF

====================================================================
 Local release artifacts ready for $VERSION
   app     : $APP  (signed, notarized, stapled)
   dmg     : $DMG
   appcast : $APPCAST
====================================================================
 Version files this touched (ALL must go in the one commit):
   player/package.json (+ lockfile), mac-app/project.yml, tv-app/project.yml,
   ipad-app/project.yml, the regenerated .xcodeproj for each, site/appcast.xml
 Next (outward, done from chat so it stays gated):
   1. Commit the version bump (INCLUDING site/appcast.xml and BOTH app
      project.yml + .xcodeproj) + tag $TAG.
   2. Create the GitHub Release and upload the dmg (asset name must stay
      OpenObject-$VERSION.dmg so the appcast URL resolves).
   3. Publish appcast.xml to gh-pages (openobject.io/appcast.xml).
   4. The frame picks $VERSION up on its next Software Update (it tracks main).
   5. App Store, only if submitting: archive + upload tvOS and iOS, then tag
      each submission (tvos-$VERSION-submitted, ios-$VERSION-submitted) so
      "what changed since the binary in review" is a one-line query.
 The full checklist, and what to do while the stores lag, is HANDOFF section 15.
 Paste the paths above back into chat and we'll finish the publish.
====================================================================
EOF

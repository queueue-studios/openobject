#!/usr/bin/env bash
set -euo pipefail

# Build a drag-to-Applications .dmg from a signed OpenObject.app, then sign, notarize, and staple
# the .dmg itself (MAC-APP-PLAN §C2). Run this AFTER sign-and-notarize.sh has signed + notarized +
# stapled the .app; this wraps that app in a disk image and gets the image its own notarization, so
# Gatekeeper is happy both on mount and after the app is copied to /Applications.
#
# Dependency-free: uses hdiutil (built into macOS), consistent with the no-extra-tools ethos. The
# window layout is intentionally plain for now (the app + an Applications alias); a branded background
# and icon positions are a later polish.
#
# Usage: build-dmg.sh <path-to-.app> [output.dmg]
# Requires: the LLC "Developer ID Application" cert in the keychain, and the notary credential
# profile "openobject-llc" (xcrun notarytool store-credentials).

APP="${1:?usage: build-dmg.sh <path-to-.app> [out.dmg]}"
OUT="${2:-$(dirname "$APP")/OpenObject.dmg}"
IDENTITY="${OO_SIGN_IDENTITY:-Developer ID Application: Queueue Studios LLC (J87JRCN9RM)}"
NOTARY_PROFILE="${OO_NOTARY_PROFILE:-openobject-llc}"
VOLNAME="OpenObject"

# --- stage the disk image contents: the app next to an Applications alias (drag one onto the other) ---
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "[dmg] creating $OUT ..."
rm -f "$OUT"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$OUT" >/dev/null

echo "[dmg] signing (Developer ID) ..."
codesign --force --timestamp --sign "$IDENTITY" "$OUT"

echo "[dmg] notarizing (waits for Apple) ..."
xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait

echo "[dmg] stapling ..."
xcrun stapler staple "$OUT"
xcrun stapler validate "$OUT"

echo "[dmg] Gatekeeper assessment:"
spctl --assess --type open --context context:primary-signature --verbose=2 "$OUT" || true

echo "[dmg] done → $OUT"

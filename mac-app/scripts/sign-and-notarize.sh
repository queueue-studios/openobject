#!/usr/bin/env bash
set -euo pipefail

# Sign (Developer ID + hardened runtime), notarize, and staple the OpenObject Mac app
# (MAC-APP-PLAN §C1/§C2). Signs inner-to-outer: the bundled `node` binary first (with V8's JIT
# entitlements), then the app bundle. Notarizes the whole thing under the Queueue Studios LLC account
# and staples the ticket so it launches offline without Gatekeeper prompts.
#
# Usage: sign-and-notarize.sh <path-to-.app>
# Requires: the LLC "Developer ID Application" cert in the keychain, and the notary credential
# profile "openobject-llc" (xcrun notarytool store-credentials).

APP="${1:?usage: sign-and-notarize.sh <path-to-.app>}"
IDENTITY="${OO_SIGN_IDENTITY:-Developer ID Application: Queueue Studios LLC (J87JRCN9RM)}"
NOTARY_PROFILE="${OO_NOTARY_PROFILE:-openobject-llc}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NODE_ENTITLEMENTS="$SCRIPT_DIR/../signing/node.entitlements"

echo "[sign] node binary (hardened runtime + JIT entitlements)…"
codesign --force --timestamp --options runtime \
  --entitlements "$NODE_ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP/Contents/Resources/node"

echo "[sign] app bundle (hardened runtime)…"
codesign --force --timestamp --options runtime \
  --sign "$IDENTITY" \
  "$APP"

echo "[verify] codesign (deep, strict)…"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "[notarize] zipping + submitting to Apple (waits for the result)…"
ZIP="$(dirname "$APP")/$(basename "$APP" .app)-notarize.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$ZIP"

echo "[staple] attaching the notarization ticket…"
xcrun stapler staple "$APP"

echo "[verify] Gatekeeper assessment (Developer ID)…"
spctl --assess --type execute --verbose=2 "$APP"

echo "[done] signed, notarized, stapled → $APP"

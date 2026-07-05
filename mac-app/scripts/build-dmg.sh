#!/usr/bin/env bash
set -euo pipefail

# Build a styled drag-to-Applications .dmg from a signed OpenObject.app, then sign, notarize, and
# staple the .dmg itself (MAC-APP-PLAN §C2). Run this AFTER sign-and-notarize.sh has signed +
# notarized + stapled the .app.
#
# The mounted window is branded: a dark OPEN / OBJECT background with a centered arrow
# (mac-app/dmg/background.png), the app icon and an Applications alias flanking that arrow at
# Firefox-size icons, and a custom volume icon on the desktop (the OpenObject-badged disk,
# mac-app/dmg/volume-icon.icns).
#
# The window styling drives Finder through AppleScript, so run this in a real login session (macOS
# may prompt once to allow controlling Finder). Otherwise dependency-free: hdiutil, sips, SetFile,
# osascript are all built into macOS.
#
# Layout knobs (Finder points; the background is 2x, so points = background pixels / 2):
#   OO_DMG_WIN="720 440"       window content size
#   OO_DMG_ICON_SIZE=128       icon size (the larger, Firefox-style icons)
#   OO_DMG_APP_POS="200 220"   app icon center (left of the arrow)
#   OO_DMG_APPS_POS="520 220"  Applications icon center (right of the arrow)
# Set OO_DMG_SKIP_NOTARIZE=1 to build the styled image only (no codesign/notarize/staple) for fast
# visual iteration on the layout.
#
# Usage: build-dmg.sh <path-to-.app> [output.dmg]
# Requires (unless OO_DMG_SKIP_NOTARIZE=1): the LLC "Developer ID Application" cert in the keychain,
# and the notary credential profile "openobject-llc" (xcrun notarytool store-credentials).

APP="${1:?usage: build-dmg.sh <path-to-.app> [out.dmg]}"
OUT="${2:-$(dirname "$APP")/OpenObject.dmg}"
IDENTITY="${OO_SIGN_IDENTITY:-Developer ID Application: Queueue Studios LLC (J87JRCN9RM)}"
NOTARY_PROFILE="${OO_NOTARY_PROFILE:-openobject-llc}"
VOLNAME="${OO_DMG_VOLNAME:-OpenObject}"   # override with a fresh name to bypass Finder's icon cache when testing

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DMG_ASSETS="$HERE/../dmg"
BG="$DMG_ASSETS/background.png"
VOLICON="$DMG_ASSETS/volume-icon.icns"
[ -f "$BG" ] || { echo "[dmg] missing background: $BG" >&2; exit 1; }
[ -f "$VOLICON" ] || { echo "[dmg] missing volume icon: $VOLICON" >&2; exit 1; }

read -r WIN_W WIN_H <<<"${OO_DMG_WIN:-720 440}"
# AppleScript window bounds include the title bar, so add it back or the content area (where the
# background is drawn) ends up shorter than the art, clipping its bottom and pushing the centered
# icons low. Tune with OO_DMG_CHROME if the bottom is still cropped or has a gap.
CHROME="${OO_DMG_CHROME:-32}"
ICON_SIZE="${OO_DMG_ICON_SIZE:-128}"
read -r APP_X APP_Y <<<"${OO_DMG_APP_POS:-200 220}"
read -r APPS_X APPS_Y <<<"${OO_DMG_APPS_POS:-520 220}"
APP_NAME="$(basename "$APP")"   # OpenObject.app

# --- stage the volume contents: app, Applications alias, background, volume icon ---
STAGE="$(mktemp -d)"
TMPDMG="$(mktemp -u).dmg"
DEV=""
cleanup(){ [ -n "${DEV:-}" ] && hdiutil detach "$DEV" -quiet 2>/dev/null || true; rm -rf "$STAGE" "$TMPDMG"; }
trap cleanup EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp "$BG" "$STAGE/.background/background.png"
# Normalize the background DPI so ImageIO (and therefore Finder) draws it at 720x440 pt as a 2x
# Retina background: point size = pixels * 72 / dpi, so 1440x880 @ 144 dpi -> 720x440 pt. Exported
# art often carries a print dpi (e.g. 300), which makes Finder draw the picture too small; force 144
# on our working copy only, never touching mac-app/dmg/background.png.
sips -s dpiWidth 144 -s dpiHeight 144 "$STAGE/.background/background.png" >/dev/null
# NOTE: .VolumeIcon.icns is intentionally NOT staged here — hdiutil create -srcfolder drops a
# root-level .VolumeIcon.icns. It is copied onto the mounted volume below instead.

# --- read-write image with slack so Finder can write the .DS_Store ---
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 50 ))
echo "[dmg] creating ${SIZE_MB}M read-write image ..."
rm -f "$TMPDMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$TMPDMG" >/dev/null

echo "[dmg] mounting ..."
DEV="$(hdiutil attach "$TMPDMG" -readwrite -noverify -noautoopen | grep -E '^/dev/' | head -1 | awk '{print $1}')"
VOL="/Volumes/$VOLNAME"

echo "[dmg] styling the Finder window ..."
REPORTED=$(osascript <<APPLESCRIPT
tell application "Finder"
  activate
  tell disk "$VOLNAME"
    open
    delay 1
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set background picture of opts to file ".background:background.png"
    set position of item "$APP_NAME" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    set the bounds of container window to {200, 140, $((200 + WIN_W)), $((140 + WIN_H + CHROME))}
    delay 1
    set reportedBounds to (bounds of container window) as string
    update without registering applications
    delay 1
    close
    return reportedBounds
  end tell
end tell
APPLESCRIPT
)
echo "[dmg] window: requested outer size ${WIN_W}x$((WIN_H + CHROME)) pt (WIN_H=$WIN_H + CHROME=$CHROME); Finder reported bounds = $REPORTED"

# Volume desktop icon (the badged disk), done LAST so no Finder activity can clobber it: (1) copy
# .VolumeIcon.icns to the volume root here, not via -srcfolder (hdiutil drops it) and not before the
# Finder styling (Finder's .DS_Store writes were deleting it), (2) stamp the 'icnC' creator, (3) set
# the volume's custom-icon attribute. The echo reports what actually stuck.
cp "$VOLICON" "$VOL/.VolumeIcon.icns"
SetFile -c icnC "$VOL/.VolumeIcon.icns" 2>/dev/null || echo "[dmg] warn: could not set icnC creator"
SetFile -a C "$VOL"
echo "[dmg] volume icon → .VolumeIcon.icns: $( [ -f "$VOL/.VolumeIcon.icns" ] && echo present || echo MISSING ) · custom-icon bit: $(GetFileInfo -aC "$VOL" 2>/dev/null || echo '?')"

sync
echo "[dmg] detaching ..."
hdiutil detach "$DEV" -quiet
DEV=""

echo "[dmg] compressing → $OUT ..."
rm -f "$OUT"
hdiutil convert "$TMPDMG" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null

if [ "${OO_DMG_SKIP_NOTARIZE:-}" = "1" ]; then
  echo "[dmg] OO_DMG_SKIP_NOTARIZE=1 → styled image only (unsigned, not notarized) → $OUT"
  exit 0
fi

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

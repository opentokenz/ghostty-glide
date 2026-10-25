#!/usr/bin/env bash
set -euo pipefail

# Package a ReleaseFast / ReleaseLocal Ghostty build as an independent app.
# This never modifies the source .app or an installed Ghostty application.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_APP="$ROOT/macos/build/ReleaseLocal/Ghostty.app"
OUT_DIR="$ROOT/zig-out/glide-release"
APP_ID="com.opentokenz.ghostty-glide"
APP_NAME="Ghostty Glide"

if [[ ! -d "$SOURCE_APP/Contents" ]]; then
  echo "Missing ReleaseLocal app. Build first: zig build -Doptimize=ReleaseFast -j4" >&2
  exit 1
fi

SHA="$(git -C "$ROOT" rev-parse --short=8 HEAD)"
SUFFIX="$SHA-macos-universal"
STAGING="$OUT_DIR/Ghostty-Glide-$SUFFIX"
APP="$STAGING/$APP_NAME.app"
DMG="$OUT_DIR/Ghostty-Glide-$SUFFIX.dmg"

if [[ -e "$APP" || -e "$DMG" ]]; then
  echo "Release destination already exists; refusing to overwrite: $STAGING or $DMG" >&2
  exit 1
fi

mkdir -p "$STAGING"
/usr/bin/ditto --rsrc --extattr "$SOURCE_APP" "$APP"

PLIST="$APP/Contents/Info.plist"
PLISTBUDDY="/usr/libexec/PlistBuddy"
"$PLISTBUDDY" -c "Set :CFBundleIdentifier $APP_ID" "$PLIST"
"$PLISTBUDDY" -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST"
if "$PLISTBUDDY" -c "Print :CFBundleName" "$PLIST" >/dev/null 2>&1; then
  "$PLISTBUDDY" -c "Set :CFBundleName $APP_NAME" "$PLIST"
else
  "$PLISTBUDDY" -c "Add :CFBundleName string $APP_NAME" "$PLIST"
fi

# This local fork must not auto-install official Ghostty updates.
if "$PLISTBUDDY" -c 'Print :SUEnableAutomaticChecks' "$PLIST" >/dev/null 2>&1; then
  "$PLISTBUDDY" -c 'Set :SUEnableAutomaticChecks false' "$PLIST"
else
  "$PLISTBUDDY" -c 'Add :SUEnableAutomaticChecks bool false' "$PLIST"
fi

# Keep the embedded extension's bundle ID separate from official Ghostty.
DOCK_PLUGIN="$APP/Contents/PlugIns/DockTilePlugin.plugin"
if [[ -d "$DOCK_PLUGIN" ]]; then
  "$PLISTBUDDY" -c "Set :CFBundleIdentifier $APP_ID.docktile" "$DOCK_PLUGIN/Contents/Info.plist"
  /usr/bin/codesign --force --sign - --timestamp=none --options runtime "$DOCK_PLUGIN"
fi

# Ad-hoc local code signature, preserving the ReleaseLocal app entitlements.
# This package is NOT developer-ID signed or Apple notarized.
/usr/bin/codesign --force --sign - --timestamp=none --options runtime \
  --entitlements "$ROOT/macos/GhosttyReleaseLocal.entitlements" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=1 "$APP"

if [[ "$("$PLISTBUDDY" -c 'Print :CFBundleIdentifier' "$PLIST")" != "$APP_ID" ]]; then
  echo "Bundle identifier validation failed" >&2
  exit 1
fi

ln -s /Applications "$STAGING/Applications"
/usr/bin/hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGING" \
  -format UDZO -imagekey zlib-level=9 "$DMG"
/usr/bin/hdiutil verify "$DMG"

printf '\nApp: %s\nDMG: %s\n' "$APP" "$DMG"
printf 'Bundle ID: %s\n' "$APP_ID"
printf 'Size: '
/usr/bin/du -h "$DMG"

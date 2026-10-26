#!/bin/bash
# Builds build/Sway.app: release binary, Info.plist, icon, ad-hoc signature
# with the hardened runtime. No Apple developer account needed.
#
#   scripts/build-app.sh            build
#   scripts/build-app.sh --install  also copy to /Applications (replaces it)
set -euo pipefail
cd "$(dirname "$0")/.."

# Use Xcode's toolchain when it works; otherwise the Command Line Tools
# (e.g. when the Xcode license hasn't been accepted yet).
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcrun swift --version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi

# Fail on a compile error: the old binary must never be packaged as new.
set +o pipefail
swift build -c release --product Sway 2>&1 | grep -v -E "PlatformPath|could not determine XCTest"
status=${PIPESTATUS[0]}
set -o pipefail
[ "$status" -eq 0 ] || { echo "build failed (swift build exit $status)"; exit 1; }
BIN="$(swift build -c release --product Sway --show-bin-path 2>/dev/null)/Sway"
[ -x "$BIN" ] || { echo "build failed: $BIN missing"; exit 1; }

APP=build/Sway.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Sway"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon, rendered by the app itself from an SF Symbol.
if [ ! -f Resources/AppIcon.icns ]; then
  TMP="$(mktemp -d)"
  "$BIN" --render-icon "$TMP" >/dev/null
  iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
  rm -rf "$TMP"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# An ad-hoc signature's default requirement is its cdhash, so every rebuild
# looked like a new app to macOS and lost the camera permission. Naming the
# bundle id as the requirement keeps the permission across rebuilds.
codesign --force --sign - --options runtime --entitlements Resources/Sway.entitlements \
  -r='designated => identifier "dev.sway.coach"' "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(du -sh "$APP" | cut -f1))"

if [ "${1:-}" = "--install" ]; then
  pkill -x Sway 2>/dev/null || true
  rm -rf /Applications/Sway.app
  cp -R "$APP" /Applications/Sway.app
  echo "Installed /Applications/Sway.app"
fi

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-release}"

echo "== full self-test =="
"$ROOT/scripts/self-test.sh" --full

echo "== release build =="
xcodebuild \
  -project "$ROOT/App/Jingli.xcodeproj" \
  -scheme Jingli \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build

APP="$BUILD_DIR/Build/Products/Release/Jingli.app"
[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }

echo "== bundle checks =="
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist"
[ -f "$APP/Contents/Resources/AppIcon.icns" ] || ls "$APP/Contents/Resources" | grep -i icns

echo "== signature =="
codesign --verify --deep --strict "$APP" && echo "signature verified"
codesign -dv "$APP" 2>&1 | grep -E "Identifier|TeamIdentifier|Authority" || true

echo
echo "release gate passed."
echo "next: scripts/release-build.sh (optional signing / zip / notarization)"
echo "tag: git tag -a v1.0.0 -m 'Release' && git push origin v1.0.0"

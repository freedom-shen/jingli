#!/usr/bin/env bash
set -euo pipefail

# 构建 Release，可选 Developer ID 签名、打包 zip、公证。
#   SIGN_IDENTITY="Developer ID Application: ... (TEAMID)" scripts/release-build.sh
#   同名证书有多张时，SIGN_IDENTITY 传 SHA-1（security find-identity -v -p codesigning）
#   NOTARY_PROFILE=jingli-notary scripts/release-build.sh    # 需先 xcrun notarytool store-credentials
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
OUT_DIR="$ROOT/artifacts/release"

xcodebuild \
  -project "$ROOT/App/Jingli.xcodeproj" \
  -scheme Jingli \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build

APP="$BUILD_DIR/Build/Products/Release/Jingli.app"
[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }

if [ -n "$SIGN_IDENTITY" ]; then
  echo "signing with $SIGN_IDENTITY"
  find "$APP" -name "*.dylib" -print0 | xargs -0 -I{} \
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "{}"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "verified: $(codesign -dv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier' | tr '\n' ' ')"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/Jingli-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "zip: $ZIP"

if [ -n "$NOTARY_PROFILE" ]; then
  echo "submitting for notarization…"
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  echo "notarized and stapled"
fi

spctl -a -vv "$APP" 2>&1 || true

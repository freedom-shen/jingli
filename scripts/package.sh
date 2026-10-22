#!/usr/bin/env bash
set -euo pipefail

# 打包并安装「精力管理」：
#   1. Release 构建（可选 Developer ID 签名）
#   2. 生成 zip 到 artifacts/release/
#   3. 安装到 /Applications（默认），替换旧版本
#
# 用法：
#   scripts/package.sh                 # 构建 + zip + 安装到 /Applications
#   scripts/package.sh --no-install    # 只打包
#   scripts/package.sh --no-zip        # 不生成 zip
#   scripts/package.sh --run           # 安装后启动
#   scripts/package.sh --install-dir ~/Applications
#   SIGN_IDENTITY=<hash 或名称> scripts/package.sh        # Developer ID 签名
#   NOTARY_PROFILE=<keychain profile> scripts/package.sh  # 额外公证

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/jingli-release}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

APP_NAME="Jingli.app"
EXECUTABLE="Jingli"
DO_ZIP=1
DO_INSTALL=1
RUN_AFTER=0

usage() {
  sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --no-zip) DO_ZIP=0 ;;
    --no-install) DO_INSTALL=0 ;;
    --run) RUN_AFTER=1 ;;
    --install-dir)
      INSTALL_DIR="${2:-}"
      [ -n "$INSTALL_DIR" ] || { echo "--install-dir 需要目录" >&2; exit 2; }
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

echo "== 1/4 release build =="
xcodebuild \
  -project "$ROOT/App/Jingli.xcodeproj" \
  -scheme Jingli \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  build > "$BUILD_DIR-build.log" 2>&1 || {
    tail -60 "$BUILD_DIR-build.log" >&2
    exit 1
  }

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME"
[ -d "$APP" ] || { echo "missing $APP" >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

echo "== 2/4 sign (version $VERSION) =="
if [ -n "$SIGN_IDENTITY" ]; then
  find "$APP" -name "*.dylib" -print0 | xargs -0 -I{} \
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "{}"
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  echo "SIGN_IDENTITY 未设置，使用构建自带的本地签名（Sign to Run Locally）"
fi
codesign --verify --deep --strict "$APP"
echo "signature ok: $(codesign -dv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier' | tr '\n' ' ')"

ZIP=""
if [ "$DO_ZIP" = "1" ] || [ -n "$NOTARY_PROFILE" ]; then
  echo "== 3/4 zip =="
  mkdir -p "$ROOT/artifacts/release"
  ZIP="$ROOT/artifacts/release/Jingli-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "zip: $ZIP"

  if [ -n "$NOTARY_PROFILE" ]; then
    echo "== 3.5/4 notarize =="
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
  fi
else
  echo "== 3/4 zip skipped =="
fi

if [ "$DO_INSTALL" = "1" ]; then
  echo "== 4/4 install to $INSTALL_DIR =="
  TARGET="$INSTALL_DIR/$APP_NAME"

  if [ ! -w "$INSTALL_DIR" ]; then
    echo "$INSTALL_DIR 不可写；请手动复制，或用 --install-dir ~/Applications" >&2
    exit 1
  fi

  if pgrep -x "$EXECUTABLE" > /dev/null; then
    echo "退出正在运行的 ${EXECUTABLE}…"
    osascript -e 'tell application "Jingli" to quit' >/dev/null 2>&1 || true
    sleep 1
    pkill -x "$EXECUTABLE" 2>/dev/null || true
    sleep 0.5
  fi

  rm -rf "$TARGET"
  ditto "$APP" "$TARGET"
  codesign --verify --deep --strict "$TARGET"

  LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$TARGET" >/dev/null 2>&1 || true
  fi

  echo "installed: $TARGET"
else
  echo "== 4/4 install skipped =="
fi

if [ "$RUN_AFTER" = "1" ] && [ "$DO_INSTALL" = "1" ]; then
  echo "启动 ${TARGET}…"
  open "$TARGET"
fi

echo
echo "打包完成"
echo "  app:    $INSTALL_DIR/$APP_NAME"
echo "  version: $VERSION"
[ -n "$ZIP" ] && echo "  zip:    $ZIP"
echo "  验证:   plutil -p \"$INSTALL_DIR/$APP_NAME/Contents/Info.plist\" | grep -E 'CFBundleShortVersionString|CFBundleIdentifier'"

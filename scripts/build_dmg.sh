#!/bin/sh
# Tests, builds Pantry.app (Swift release build) and packages it into build/Pantry.dmg.
#
# Prerequisites (run on a Mac):
#   - Xcode Command Line Tools (for `swift`): xcode-select --install
#
# Usage:
#   ./scripts/build_dmg.sh                    test + build + dmg (ad-hoc signed)
#   ./scripts/build_dmg.sh --skip-tests       build + dmg only
#   ./scripts/build_dmg.sh --sign "Developer ID Application: Name (TEAMID)" [--notarize PROFILE]
#     (--notarize needs a profile made once with: xcrun notarytool store-credentials PROFILE)
set -eu

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_NAME="Pantry"
# Must match the executable target name in Package.swift. A mismatch does not fail
# the build; the check in step 2 catches it instead of packaging a stale binary.
SWIFT_PRODUCT_NAME="Pantry"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
BUNDLE_ID="dev.local.pantry"
VERSION="0.1.0"

SKIP_TESTS=0
IDENTITY=""
NOTARY_PROFILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-tests) SKIP_TESTS=1; shift ;;
    --sign) [ $# -ge 2 ] || { echo "error: --sign needs an identity" >&2; exit 1; }; IDENTITY="$2"; shift 2 ;;
    --notarize) [ $# -ge 2 ] || { echo "error: --notarize needs a profile" >&2; exit 1; }; NOTARY_PROFILE="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "error: unknown option $1 (try --help)" >&2; exit 1 ;;
  esac
done
[ -z "$NOTARY_PROFILE" ] || [ -n "$IDENTITY" ] || { echo "error: --notarize requires --sign" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || { echo "error: run this on macOS." >&2; exit 1; }
command -v swift >/dev/null 2>&1 || { echo "error: 'swift' not found. Install Xcode Command Line Tools." >&2; exit 1; }

cd "$ROOT_DIR"

if [ "$SKIP_TESTS" -eq 0 ]; then
  echo "==> [1/6] Testing"
  mkdir -p "$BUILD_DIR"
  TEST_LOG="$BUILD_DIR/test.log"
  # POSIX sh has no pipefail, so write to the log, follow it live with tail, and keep swift's exit code.
  : > "$TEST_LOG"
  tail -f "$TEST_LOG" &
  TAIL_PID=$!
  TEST_RC=0
  swift test > "$TEST_LOG" 2>&1 || TEST_RC=$?
  sleep 1
  kill "$TAIL_PID" 2>/dev/null || true
  wait "$TAIL_PID" 2>/dev/null || true
  if [ "$TEST_RC" -ne 0 ]; then
    echo ""
    echo "==> TESTS FAILED. Summary:"
    # XCTest failures and compile errors both contain ": error:".
    grep -E ": error:" "$TEST_LOG" | sed "s#$ROOT_DIR/##" | awk '!seen[$0]++' | head -60 || true
    grep -E "Executed [0-9]+ tests?, with" "$TEST_LOG" | tail -1 || true
    echo ""
    echo "Full log: $TEST_LOG"
    echo "To build the DMG anyway: ./scripts/build_dmg.sh --skip-tests"
    exit 1
  fi
else
  echo "==> [1/6] Skipping tests (--skip-tests)"
fi

echo "==> [2/6] Building release"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
SWIFT_BINARY="$BIN_DIR/$SWIFT_PRODUCT_NAME"
if [ ! -x "$SWIFT_BINARY" ]; then
  echo "error: expected release binary not found at $SWIFT_BINARY" >&2
  echo "       (check Package.swift's executable target name against SWIFT_PRODUCT_NAME" >&2
  echo "       at the top of this script)" >&2
  exit 1
fi

echo "==> [3/6] Assembling $APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$SWIFT_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# SwiftPM resource bundle, if the target ever gains resources (none today).
SWIFT_RESOURCE_BUNDLE="$BIN_DIR/${SWIFT_PRODUCT_NAME}_${SWIFT_PRODUCT_NAME}.bundle"
if [ -d "$SWIFT_RESOURCE_BUNDLE" ]; then cp -R "$SWIFT_RESOURCE_BUNDLE" "$APP_BUNDLE/Contents/Resources/"; fi

# Icons live in resources/. The app icon is wired through Info.plist; the menu bar
# glyph (1x + @2x, template image) is loaded at runtime from Contents/Resources.
RES_DIR="$ROOT_DIR/resources"
for f in AppIcon.icns MenuBarGlyph.png MenuBarGlyph@2x.png MenuBarGlyph-LICENSE.txt; do
  if [ ! -f "$RES_DIR/$f" ]; then
    echo "error: resources/$f is missing; the icons must be present to build." >&2
    exit 1
  fi
  cp "$RES_DIR/$f" "$APP_BUNDLE/Contents/Resources/$f"
done
ICON_PLIST_ENTRY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key>
    <true/>
$ICON_PLIST_ENTRY
</dict>
</plist>
PLIST

if [ -n "$IDENTITY" ]; then
  echo "==> [4/6] Code signing with: $IDENTITY"
  codesign --deep --force --options runtime --timestamp --sign "$IDENTITY" "$APP_BUNDLE"
else
  echo "==> [4/6] Ad-hoc code signing (local use; not notarized)"
  codesign --deep --force --sign - "$APP_BUNDLE"
fi

echo "==> [5/6] Staging DMG contents"
STAGE_DIR="$BUILD_DIR/dmg-stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_BUNDLE" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "==> [6/6] Creating $APP_NAME.dmg"
rm -f "$BUILD_DIR/$APP_NAME.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE_DIR" -ov -format UDZO "$BUILD_DIR/$APP_NAME.dmg"
rm -rf "$STAGE_DIR"

if [ -n "$IDENTITY" ]; then
  codesign --force --timestamp --sign "$IDENTITY" "$BUILD_DIR/$APP_NAME.dmg"
fi
if [ -n "$NOTARY_PROFILE" ]; then
  echo "==> Notarizing (a few minutes)"
  xcrun notarytool submit "$BUILD_DIR/$APP_NAME.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$BUILD_DIR/$APP_NAME.dmg"
fi

echo ""
echo "Done: $BUILD_DIR/$APP_NAME.dmg"
if [ -z "$IDENTITY" ]; then
  echo "Note: ad-hoc signed for local use. On another Mac, right-click the app and choose Open once."
fi

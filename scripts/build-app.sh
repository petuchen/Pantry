#!/bin/bash
# Builds Pantry.app (Apple Silicon, ad-hoc signed) into ./dist.
# Run on a Mac with Xcode or the Swift 5.9+ toolchain installed.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Pantry"
BUNDLE_ID="dev.local.pantry"
VERSION="0.1.0"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="dist/${APP_NAME}.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "${BIN_DIR}/${APP_NAME}" "$APP/Contents/MacOS/${APP_NAME}"
for f in AppIcon.icns MenuBarGlyph.png MenuBarGlyph@2x.png MenuBarGlyph-LICENSE.txt; do
  [ -f "resources/$f" ] || { echo "error: resources/$f is missing" >&2; exit 1; }
  cp "resources/$f" "$APP/Contents/Resources/$f"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleName</key><string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key><string>${APP_NAME}</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so Gatekeeper lets a locally built app run. Not notarised.
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Open it with:  open \"$APP\""

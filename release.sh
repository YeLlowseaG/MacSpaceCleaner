#!/bin/bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="${DIST_DIR:-$SOURCE_DIR/dist}"
APP_NAME="Mac 空间清理"
APP_PATH="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/MacSpaceCleaner-1.2.dmg"
STAGING_DIR="$DIST_DIR/dmg-root"
BUILD_DIR="$DIST_DIR/build"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ICONSET="$BUILD_DIR/AppIcon.iconset"
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: HUANG HAI (P3U8WS99Q3)}"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$SIGN_IDENTITY\""; then
  echo "找不到签名身份：$SIGN_IDENTITY" >&2
  exit 1
fi

rm -rf "$APP_PATH" "$STAGING_DIR" "$BUILD_DIR" "$DMG_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET" "$BUILD_DIR/arm64" "$BUILD_DIR/x86_64" "$STAGING_DIR"

for arch in arm64 x86_64; do
  xcrun --sdk macosx swiftc \
    -swift-version 5 \
    -target "$arch-apple-macos14.0" \
    -parse-as-library \
    -framework SwiftUI \
    -framework AppKit \
    "$SOURCE_DIR/MacSpaceCleaner.swift" \
    -o "$BUILD_DIR/$arch/MacSpaceCleaner"
done

lipo -create \
  "$BUILD_DIR/arm64/MacSpaceCleaner" \
  "$BUILD_DIR/x86_64/MacSpaceCleaner" \
  -output "$MACOS_DIR/MacSpaceCleaner"

xcrun --sdk macosx swiftc \
  -target arm64-apple-macos14.0 \
  -framework AppKit \
  "$SOURCE_DIR/IconGenerator.swift" \
  -o "$BUILD_DIR/IconGenerator"

"$BUILD_DIR/IconGenerator" "$BUILD_DIR/AppIcon-1024.png"

for spec in \
  "16 icon_16x16.png" \
  "32 icon_16x16@2x.png" \
  "32 icon_32x32.png" \
  "64 icon_32x32@2x.png" \
  "128 icon_128x128.png" \
  "256 icon_128x128@2x.png" \
  "256 icon_256x256.png" \
  "512 icon_256x256@2x.png" \
  "512 icon_512x512.png" \
  "1024 icon_512x512@2x.png"
do
  pixels="${spec%% *}"
  filename="${spec#* }"
  sips -z "$pixels" "$pixels" "$BUILD_DIR/AppIcon-1024.png" --out "$ICONSET/$filename" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
cp "$SOURCE_DIR/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist"

codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

rm -rf "$STAGING_DIR" "$BUILD_DIR"

echo "发布 App：$APP_PATH"
echo "发布 DMG：$DMG_PATH"

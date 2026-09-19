#!/bin/bash
set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="/Users/yellow/Desktop/Mac 空间清理.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
ICONSET="$SOURCE_DIR/AppIcon.iconset"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET"

swiftc \
  -swift-version 5 \
  -target arm64-apple-macos14.0 \
  -parse-as-library \
  -framework SwiftUI \
  -framework AppKit \
  "$SOURCE_DIR/MacSpaceCleaner.swift" \
  -o "$MACOS_DIR/MacSpaceCleaner"

swiftc \
  -target arm64-apple-macos14.0 \
  -framework AppKit \
  "$SOURCE_DIR/IconGenerator.swift" \
  -o "$SOURCE_DIR/IconGenerator"

"$SOURCE_DIR/IconGenerator" "$SOURCE_DIR/AppIcon-1024.png"

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
  sips -z "$pixels" "$pixels" "$SOURCE_DIR/AppIcon-1024.png" --out "$ICONSET/$filename" >/dev/null
done

iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
cp "$SOURCE_DIR/Info.plist" "$CONTENTS/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" 2>/dev/null || \
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS/Info.plist"

codesign --force --deep --sign - "$APP_PATH"
touch "$APP_PATH"
echo "$APP_PATH"


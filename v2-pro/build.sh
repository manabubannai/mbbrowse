#!/bin/bash
# Mado Pro v2 ビルド — Xcode不要、Command Line Toolsのみ
set -euo pipefail
cd "$(dirname "$0")"

APP="Mado Pro"
BUNDLE="$APP.app"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

swiftc -O -parse-as-library \
  -target arm64-apple-macosx14.0 \
  -framework AppKit -framework WebKit \
  -o "$BUNDLE/Contents/MacOS/Mado Pro" \
  mbbrowse.swift

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Mado Pro</string>
  <key>CFBundleDisplayName</key><string>Mado Pro</string>
  <key>CFBundleIdentifier</key><string>com.manabu.mbbrowse</string>
  <key>CFBundleVersion</key><string>1.1.0</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleExecutable</key><string>Mado Pro</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© manabu</string>
</dict>
</plist>
PLIST

if [ -f AppIcon.icns ]; then
  cp AppIcon.icns "$BUNDLE/Contents/Resources/"
fi

codesign --force --deep --sign - "$BUNDLE"
echo "✅ ビルド完了: $(pwd)/$BUNDLE"

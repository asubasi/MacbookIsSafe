#!/bin/bash
# HingeGuard.app paketini ve dağıtım için DMG'yi oluşturur.
# Kullanım: ./scripts/make-dmg.sh   ->   dist/HingeGuard-<sürüm>.dmg
set -euo pipefail

VERSION="0.1.0"
BUNDLE_ID="com.hingeguard.app"
APP_NAME="HingeGuard"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
WORK="$DIST/work"
APP="$WORK/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

cd "$ROOT"
rm -rf "$WORK" "$DMG"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> Release derlemesi"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

echo "==> Simge"
swift scripts/make-icon.swift "$WORK/$APP_NAME.iconset" >/dev/null
iconutil -c icns "$WORK/$APP_NAME.iconset" -o "$APP/Contents/Resources/$APP_NAME.icns"

echo "==> Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>        <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>         <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>         <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>           <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>     <string>14.0</string>
    <key>LSApplicationCategoryType</key>  <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSHumanReadableCopyright</key>   <string>Kişisel kullanım için.</string>
</dict>
</plist>
PLIST

echo "==> Ad-hoc imza"
# Apple Developer kimliği yok: ad-hoc imza. Kendi Mac'inde sorunsuz çalışır,
# başka Mac'lerde ilk açılışta Gatekeeper uyarısı çıkar.
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

echo "==> DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

rm -rf "$STAGE" "$WORK/$APP_NAME.iconset"
echo "==> Hazır: $DMG"

#!/usr/bin/env bash
# Builds Matte.app into ./build and (optionally) installs it.
#   ./build.sh            build only
#   ./build.sh --install  build, then install to /Applications and launch
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Matte"
BUNDLE_ID="so.whatmatters.displaypadding"
EXECUTABLE="Matte"
VERSION="1.0.0"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling"
swift build -c release

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"

echo "==> Building icon"
swift Tools/makeicon.swift "$BUILD_DIR/icon" >/dev/null
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp "$BUILD_DIR/icon/icon_16.png"   "$ICONSET/icon_16x16.png"
cp "$BUILD_DIR/icon/icon_32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$BUILD_DIR/icon/icon_32.png"   "$ICONSET/icon_32x32.png"
cp "$BUILD_DIR/icon/icon_64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$BUILD_DIR/icon/icon_128.png"  "$ICONSET/icon_128x128.png"
cp "$BUILD_DIR/icon/icon_256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$BUILD_DIR/icon/icon_256.png"  "$ICONSET/icon_256x256.png"
cp "$BUILD_DIR/icon/icon_512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$BUILD_DIR/icon/icon_512.png"  "$ICONSET/icon_512x512.png"
cp "$BUILD_DIR/icon/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT Licensed</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP/Contents/PkgInfo"

# A stable signing identity matters beyond distribution: macOS keys the
# Accessibility grant to the code signature, so an ad-hoc signature (which is
# just the binary's hash) invalidates the grant on every rebuild.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)"/\1/')"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -m1 "Apple Development" | sed -E 's/.*"(.*)"/\1/')"
fi

if [[ -n "$SIGN_ID" ]]; then
  echo "==> Signing with: $SIGN_ID"
  codesign --force --sign "$SIGN_ID" --identifier "$BUNDLE_ID" --options runtime --timestamp "$APP"
  STABLE_SIGNATURE=1
else
  echo "==> Signing (ad-hoc — the Accessibility grant will reset on every rebuild)"
  codesign --force --sign - --identifier "$BUNDLE_ID" --options runtime --timestamp=none "$APP" 2>/dev/null \
    || codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
  STABLE_SIGNATURE=0
fi

echo "==> Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  echo "==> Installing to /Applications"
  pkill -x "$EXECUTABLE" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" "/Applications/$APP_NAME.app"

  if [[ "$STABLE_SIGNATURE" -eq 0 ]]; then
    # An ad-hoc signature is the binary's hash, so a rebuild invalidates the
    # grant. macOS leaves the toggle switched on but denies the app, which looks
    # like a bug — clearing the entry forces an honest prompt instead.
    echo "==> Clearing the stale Accessibility grant"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
  fi

  open "/Applications/$APP_NAME.app"
  echo
  echo "==> Launched. Look for the icon in your menu bar."
  if [[ "$STABLE_SIGNATURE" -eq 0 ]]; then
    echo "    Re-grant Accessibility when prompted:"
    echo "    System Settings > Privacy & Security > Accessibility > Matte"
  else
    echo "    The Accessibility grant carries across rebuilds with this signature."
  fi
fi

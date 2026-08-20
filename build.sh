#!/usr/bin/env bash
# Builds Matte.app into ./build and (optionally) installs it.
#   ./build.sh            build only
#   ./build.sh --install  build, then install to /Applications and launch
#   ./build.sh --release  build, notarize, staple, and produce a shippable zip
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Matte"
BUNDLE_ID="so.whatmatters.matte"
EXECUTABLE="Matte"
VERSION="1.0.0"
NOTARY_PROFILE="matte-notary"
TEAM_ID="4P6GX328VY"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

echo "==> Compiling"
swift build -c release

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"

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
    <key>ATSApplicationFontsPath</key><string>Fonts</string>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 WhatMatters. All rights reserved.</string>
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

  # macOS keys the Accessibility grant to the code signature, so when that
  # changes the System Settings toggle stays switched on while the app is
  # silently denied — indistinguishable from an app bug. Track what signed the
  # last install and clear the entry when it differs, so the prompt is honest.
  #
  # A real identity is stable across rebuilds, so key on the Authority alone.
  # An ad-hoc signature has no identity and TCC falls back to the binary hash,
  # which changes every build — so key on that and accept the re-grant.
  # Capture first, then filter: piping codesign straight into grep -m1 makes
  # grep close the pipe early, and pipefail turns that SIGPIPE into a failure
  # that set -e treats as fatal.
  SIGNATURE_INFO="$(codesign -dvvv "/Applications/$APP_NAME.app" 2>&1 || true)"
  if [[ "$STABLE_SIGNATURE" -eq 1 ]]; then
    CURRENT_SIGNATURE="$(printf '%s\n' "$SIGNATURE_INFO" | grep "^Authority=" | head -1 || true)"
  else
    CURRENT_SIGNATURE="adhoc:$(printf '%s\n' "$SIGNATURE_INFO" | grep "^CDHash=" | head -1 || true)"
  fi

  SIGNATURE_STATE="$HOME/Library/Application Support/$APP_NAME/last-signature"
  PREVIOUS_SIGNATURE="$(cat "$SIGNATURE_STATE" 2>/dev/null || true)"

  if [[ "$CURRENT_SIGNATURE" != "$PREVIOUS_SIGNATURE" ]]; then
    [[ -n "$PREVIOUS_SIGNATURE" ]] && echo "==> Signature changed — clearing the stale Accessibility grant"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    NEEDS_GRANT=1
  else
    NEEDS_GRANT=0
  fi
  mkdir -p "$(dirname "$SIGNATURE_STATE")"
  printf '%s' "$CURRENT_SIGNATURE" > "$SIGNATURE_STATE"

  open "/Applications/$APP_NAME.app"
  echo
  echo "==> Launched. Look for the icon in your menu bar."
  if [[ "$NEEDS_GRANT" -eq 1 ]]; then
    echo "    Grant Accessibility when prompted:"
    echo "    System Settings > Privacy & Security > Accessibility > $APP_NAME"
    echo "    Then verify: \"/Applications/$APP_NAME.app/Contents/MacOS/$EXECUTABLE\" --status"
  else
    echo "    The Accessibility grant carried across this rebuild."
  fi
fi

if [[ "${1:-}" == "--release" ]]; then
  # Gatekeeper blocks an un-notarized app the moment it arrives on another Mac
  # by any route that sets the quarantine flag — download, AirDrop, cloud sync.
  # Notarization is an automated malware scan, not App Review.
  if [[ "$STABLE_SIGNATURE" -eq 0 ]]; then
    echo "!!  Ad-hoc signed — notarization needs a Developer ID certificate." >&2
    exit 1
  fi

  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    cat >&2 <<HELP
!!  No notarization credentials stored under the profile "$NOTARY_PROFILE".

    Create an app-specific password at appleid.apple.com
    (Sign-In and Security > App-Specific Passwords), then run:

      xcrun notarytool store-credentials "$NOTARY_PROFILE" \\
        --apple-id "<your-apple-id>" \\
        --team-id "$TEAM_ID" \\
        --password "<app-specific-password>"

    The password is kept in your keychain, never in this repo.
HELP
    exit 1
  fi

  ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
  echo "==> Submitting to Apple for notarization (usually a few minutes)"
  ditto -c -k --keepParent "$APP" "$BUILD_DIR/submit.zip"
  xcrun notarytool submit "$BUILD_DIR/submit.zip" \
    --keychain-profile "$NOTARY_PROFILE" --wait
  rm -f "$BUILD_DIR/submit.zip"

  echo "==> Stapling the ticket"
  xcrun stapler staple "$APP"

  echo "==> Verifying"
  spctl -a -vvv "$APP" 2>&1 | sed 's/^/    /'
  xcrun stapler validate "$APP" 2>&1 | tail -1 | sed 's/^/    /'

  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo
  echo "==> Shippable: $ZIP"
  echo "    This can be downloaded or AirDropped and will open without warnings."
fi

#!/bin/zsh
# Builds Celah.app into ./build.
# Usage: ./build.sh [--debug] [--zip] [--install] [--run]
set -e
cd "${0:A:h}"
APP=build/Celah.app
OPT="-O"; [[ "$*" == *--debug* ]] && OPT="-Onone"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SRCS=(Sources/**/*.swift)
swiftc $OPT -swift-version 5 -target arm64-apple-macos14.0 $SRCS -o "$APP/Contents/MacOS/Celah" \
  -framework Cocoa -framework SwiftUI -framework CoreLocation \
  -framework UserNotifications -framework ServiceManagement -framework IOKit -framework ScreenCaptureKit -framework AVFoundation -framework CoreMedia
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/. "$APP/Contents/Resources/"
if [ ! -f build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset; mkdir -p build/AppIcon.iconset
  swift scripts/icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with a stable local identity when there is one, so macOS keeps Camera, Microphone and Screen Recording
# permissions across rebuilds (an ad-hoc signature changes every build, which silently revokes them).
#   One-time setup: a self-signed "Celah Local Signing" code-signing certificate in the login keychain.
SIGN_ID=$(security find-identity -p codesigning 2>/dev/null | awk -F'"' '/Celah Local Signing/ {print $0; exit}' | awk '{print $2}')
if [ -n "$SIGN_ID" ]; then
  codesign --force --deep -s "$SIGN_ID" "$APP" >/dev/null 2>&1 || codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
else
  codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
fi
echo "Built $APP"
if [[ "$*" == *--zip* ]]; then
  rm -f build/Celah.zip; ditto -c -k --keepParent "$APP" build/Celah.zip; echo "Zipped build/Celah.zip"
fi
if [[ "$*" == *--install* ]]; then
  mkdir -p ~/Applications; rm -rf ~/Applications/Celah.app; cp -R "$APP" ~/Applications/Celah.app
  echo "Installed ~/Applications/Celah.app"
fi
if [[ "$*" == *--run* ]]; then
  pkill -x Celah 2>/dev/null || true; sleep 0.4
  if [[ "$*" == *--install* ]]; then open ~/Applications/Celah.app; else open "$APP"; fi
fi

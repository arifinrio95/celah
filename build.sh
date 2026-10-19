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
codesign --force --deep -s - "$APP" >/dev/null 2>&1 || true
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

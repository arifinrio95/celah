#!/bin/bash
# Installs the latest Celah release into /Applications (or ~/Applications) and opens it.
#   curl -fsSL https://raw.githubusercontent.com/arifinrio95/celah/main/install.sh | bash
set -euo pipefail
REPO="arifinrio95/celah"
[ "$(uname)" = "Darwin" ] || { echo "Celah runs on macOS only."; exit 1; }
[ "$(uname -m)" = "arm64" ] || { echo "Celah is built for Apple silicon Macs."; exit 1; }
VER=$(sw_vers -productVersion); MAJOR=${VER%%.*}
[ "$MAJOR" -ge 14 ] || { echo "Celah needs macOS 14 Sonoma or newer (you have $VER)."; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
echo "Downloading Celah…"
curl -fsSL "https://github.com/$REPO/releases/latest/download/Celah.zip" -o "$TMP/Celah.zip"
ditto -x -k "$TMP/Celah.zip" "$TMP"
DEST="/Applications"; [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
pkill -x Celah 2>/dev/null || true
rm -rf "$DEST/Celah.app"
ditto "$TMP/Celah.app" "$DEST/Celah.app"
xattr -dr com.apple.quarantine "$DEST/Celah.app" 2>/dev/null || true
echo "Installed $DEST/Celah.app — hover the notch."
open "$DEST/Celah.app"

#!/bin/bash
# HCFR Colorimeter for macOS — Copyright (C) 2026 Jorge Velázquez — GNU GPL v2 (see LICENSE)
#
# Builds the app (build-app.sh) and packs it in "HCFR for macOS <version>.dmg": opening the DMG
# shows the app and an Applications shortcut, so installing is dragging one onto the other.
# Usage: bash make-dmg.sh            (builds first)
#        bash make-dmg.sh --no-build (packs the app already in this folder)
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
[ "$1" = "--no-build" ] || bash ./build-app.sh
APP="$ROOT/HCFR for macOS.app"
[ -d "$APP" ] || { echo "HCFR for macOS.app not found: run build-app.sh first"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
NAME="HCFR for macOS $VERSION"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/HCFR for macOS.app"
ln -s /Applications "$STAGE/Applications"
cp LICENSE "$STAGE/LICENSE.txt"
DMG="$ROOT/$NAME.dmg"
rm -f "$DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
echo "Done: $DMG"

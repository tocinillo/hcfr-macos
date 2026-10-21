#!/bin/bash
# HCFR Colorimeter for macOS — Copyright (C) 2026 Jorge Velázquez — GNU GPL v2 (see LICENSE)
#
# Builds everything and creates "HCFR Colorimeter.app" (universal, macOS 14+) in this folder.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
./build-meter.sh
# Universal binary: Apple Silicon (arm64) + Intel (x86_64)
SWIFT_FLAGS=(-c release --arch arm64 --arch x86_64)
swift build "${SWIFT_FLAGS[@]}"
# Where the binary ends up depends on the Swift toolchain (.build/release, .build/apple/Products/Release, …)
BIN_DIR="$(swift build "${SWIFT_FLAGS[@]}" --show-bin-path)"
APP="$ROOT/HCFR Colorimeter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HCFRColorimeter" "$APP/Contents/MacOS/HCFRColorimeter"
cp .build/meter/hcfr-meter "$APP/Contents/MacOS/hcfr-meter"
# HCFR CCSS display corrections (third_party/hcfr/Install/color); the helper finds them via XDG_DATA_DIRS
cp -R Resources/ArgyllCMS "$APP/Contents/Resources/ArgyllCMS"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# HCFR's test pattern images (Patterns menu), from HCFR's res/patterns
cp -R Resources/Patterns "$APP/Contents/Resources/Patterns"
# Interface translations (English keys, Spanish)
cp -R Resources/en.lproj Resources/es.lproj "$APP/Contents/Resources/"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>HCFR Colorimeter</string>
  <key>CFBundleDisplayName</key><string>HCFR Colorimeter</string>
  <key>CFBundleIdentifier</key><string>org.hcfr.colorimeterexpress</string>
  <key>CFBundleExecutable</key><string>HCFRColorimeter</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Jorge Velázquez, Mazatlán, México. Mac version based on HCFR. GNU GPL v2.</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>es</string></array>
  <key>CFBundleShortVersionString</key><string>1.3.1</string>
  <key>CFBundleVersion</key><string>5</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>HCFR Colorimeter looks for and connects to a Raspberry Pi running PGenerator on your local network to show the test patterns.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>UTExportedTypeDeclarations</key><array><dict>
    <key>UTTypeIdentifier</key><string>org.hcfr.colorimeterexpress.project</string>
    <key>UTTypeDescription</key><string>HCFR Colorimeter Project</string>
    <key>UTTypeConformsTo</key><array><string>public.json</string></array>
    <key>UTTypeIconFile</key><string>AppIcon</string>
    <key>UTTypeTagSpecification</key><dict>
      <key>public.filename-extension</key><array><string>hcfrex</string></array>
    </dict>
  </dict></array>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>org.hcfr.colorimeterexpress.automation</string>
    <key>CFBundleURLSchemes</key><array><string>hcfr</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>HCFR Colorimeter Project</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSHandlerRank</key><string>Owner</string>
    <key>LSItemContentTypes</key><array><string>org.hcfr.colorimeterexpress.project</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force --sign - "$APP/Contents/MacOS/hcfr-meter"
codesign --force --sign - "$APP"
echo "Done: $APP"
echo "Architectures: app $(lipo -archs "$APP/Contents/MacOS/HCFRColorimeter"), meter helper $(lipo -archs "$APP/Contents/MacOS/hcfr-meter")"

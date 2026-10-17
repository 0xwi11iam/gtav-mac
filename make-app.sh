#!/bin/sh
# GTA V (muguet) — macOS bundle assembly
set -eu
cd "$(dirname "$0")"
APP="$PWD/build/GTA V.app"
cargo build --release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp target/release/muguet target/release/muguet-server "$APP/Contents/MacOS/"
if [ -x "$APP/Contents/MacOS/Launcher" ] && [ "$APP/Contents/MacOS/Launcher" -nt launcher/Launcher.swift ]; then :; else
  swiftc -O -parse-as-library -target arm64-apple-macos14 launcher/Launcher.swift -o "$APP/Contents/MacOS/Launcher"
fi
cp assets/*.mp3 "$APP/Contents/Resources/" 2>/dev/null || true
[ -f build/AppIcon.icns ] && cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" || true
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>GTA V</string>
  <key>CFBundleDisplayName</key><string>GTA V</string>
  <key>CFBundleIdentifier</key><string>ch.cclerc.muguet</string>
  <key>CFBundleExecutable</key><string>Launcher</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
  <key>GCSupportsGameMode</key><true/>
  <key>NSLocalNetworkUsageDescription</key><string>Multiplayer connects to a game server on your local network.</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticGraphicsSwitching</key><false/>
  <key>MuguetEmbeddedCode</key><false/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "built: $APP ($(du -sh "$APP" | cut -f1))"

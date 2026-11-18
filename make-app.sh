#!/bin/bash
# Build this fork of SpotMenu as an ad-hoc signed .app without Xcode.
#   ./make-app.sh              → build SpotMenu.app in the project root
#   ./make-app.sh --install    → also install to ~/Applications and relaunch
#
# Differences from upstream's Xcode build: its own bundle id (so it never collides with
# the Homebrew cask's prefs or TCC grants), no Sparkle (so it never "updates" itself back
# to upstream), and the same sandbox entitlements minus Sparkle's XPC exceptions.
set -euo pipefail
cd "$(dirname "$0")"

APP="SpotMenu.app"
BIN="SpotMenu"
ID="codes.charlie.spotmenu"
VERSION="2.3.0-charlie.1"
SDKS=/Library/Developer/CommandLineTools/SDKs

# CLT 27's default SDK needs a SwiftUI macro plugin it doesn't ship. Probe each SDK with a
# one-line @State file and use the first that compiles, so this heals itself when Apple
# ships the plugin.
probe="$(mktemp -d)/probe.swift"
printf 'import SwiftUI\nstruct P: View { @State var x = 0; var body: some View { Text("") } }\n' > "$probe"
SDK=""
for cand in "$SDKS/MacOSX.sdk" $(ls -d "$SDKS"/MacOSX[0-9]*.sdk | sort -rV); do
    if SDKROOT="$cand" swiftc -typecheck "$probe" 2>/dev/null; then SDK="$cand"; break; fi
done
[[ -n "$SDK" ]] || { echo "✗ no installed SDK compiles SwiftUI @State"; exit 1; }
echo "▸ SDK: ${SDK##*/}"
export SDKROOT="$SDK"

echo "▸ Building release binary…"
swift build -c release 2>&1 | grep -E "error|warning: unre|Build complete" || true
BINPATH="$(swift build -c release --show-bin-path)"
[[ -x "$BINPATH/$BIN" ]] || { echo "✗ build failed"; exit 1; }

echo "▸ Assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINPATH/$BIN" "$APP/Contents/MacOS/$BIN"
cp -R "$BINPATH/KeyboardShortcuts_KeyboardShortcuts.bundle" "$APP/Contents/Resources/"

# No actool without Xcode: build the .icns with iconutil and copy the player icons as
# loose PNGs, which Image("SpotifyIcon") finds in Contents/Resources.
ASSETS=SpotMenu/Assets.xcassets
ICONSET="$(mktemp -d)/SpotMenu.iconset"
mkdir -p "$ICONSET"
cp "$ASSETS"/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/SpotMenu.icns"
for set in SpotifyIcon AppleMusicIcon; do
    cp "$ASSETS/$set.imageset/"*.png "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>               <string>SpotMenu</string>
    <key>CFBundleDisplayName</key>        <string>SpotMenu</string>
    <key>CFBundleIdentifier</key>         <string>$ID</string>
    <key>CFBundleExecutable</key>         <string>$BIN</string>
    <key>CFBundleIconFile</key>           <string>SpotMenu</string>
    <key>CFBundlePackageType</key>        <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>$VERSION</string>
    <key>CFBundleVersion</key>            <string>$VERSION</string>
    <key>CFBundleDevelopmentRegion</key>  <string>en</string>
    <key>LSMinimumSystemVersion</key>     <string>13.0</string>
    <key>LSUIElement</key>                <true/>
    <key>NSHighResolutionCapable</key>    <true/>
    <key>NSPrincipalClass</key>           <string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>This app needs permission to control Spotify / Apple Music using AppleScript.</string>
    <!-- Same scheme as upstream so an existing Spotify developer app's redirect URI still works. -->
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>    <string>$ID</string>
            <key>CFBundleURLSchemes</key> <array><string>com.github.kmikiy.spotmenu</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST

echo "▸ Ad-hoc signing (sandboxed)…"
codesign --force --sign - --entitlements fork/SpotMenu.entitlements --options runtime "$APP"
codesign --verify --strict "$APP"
echo "✓ Built $APP ($VERSION)"

if [[ "${1:-}" == "--install" || "${1:-}" == "install" ]]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
    echo "▸ Installing to $DEST…"
    pkill -x "$BIN" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST/$APP"
    cp -R "$APP" "$DEST/"
    LSREG=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
    "$LSREG" -u "$PWD/$APP" 2>/dev/null || true
    rm -rf "$APP"
    open "$DEST/$APP"
    echo "✓ Installed + launched $DEST/$APP"
fi

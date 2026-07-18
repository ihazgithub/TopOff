#!/bin/bash
# -e: exit on error; -u: unset vars are errors; -o pipefail: a pipeline
# fails if ANY stage fails. Without pipefail, `xcodebuild ... | tail -3`
# reports tail's exit status (0) even when the build fails, and the
# script would happily sign + notarize a stale app from a previous build.
set -euo pipefail

# TopOff DMG Builder
# Usage: ./build-dmg.sh [version]
# Example: ./build-dmg.sh 1.4.2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/TopOff"
BUILD_DIR="$SCRIPT_DIR/build"
ASSETS_DIR="$SCRIPT_DIR/assets/dmg"
BG_IMAGE="$ASSETS_DIR/background.png"
VOLUME_ICON="$ASSETS_DIR/volume-icon.icns"

SIGNING_IDENTITY="Developer ID Application: Malsah Labs LLC (GN4XAZC5QR)"
NOTARY_PROFILE="malsah-labs-notary"

# Get version from argument or read from project
if [ -n "${1:-}" ]; then
    VERSION="$1"
else
    VERSION=$(grep 'MARKETING_VERSION' "$PROJECT_DIR/TopOff.xcodeproj/project.pbxproj" | head -1 | sed 's/.*= //' | sed 's/;.*//' | tr -d ' ')
    echo "No version specified, using project version: $VERSION"
fi

DMG_NAME="TopOff-v${VERSION}.dmg"
DMG_FINAL="$SCRIPT_DIR/$DMG_NAME"
DMG_RW="/tmp/TopOff-rw.dmg"
MOUNT_POINT="/Volumes/TopOff"

echo "==> Building TopOff v${VERSION} (Universal Binary)"

# Build universal binary
echo "==> Compiling for arm64 + x86_64..."
xcodebuild -project "$PROJECT_DIR/TopOff.xcodeproj" \
    -scheme TopOff \
    -configuration Release \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64 x86_64" \
    build 2>&1 | tail -3

# Find the built app
RELEASE_APP=$(xcodebuild -project "$PROJECT_DIR/TopOff.xcodeproj" \
    -scheme TopOff \
    -configuration Release \
    -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
RELEASE_APP="$RELEASE_APP/TopOff.app"

# Verify universal binary
echo "==> Verifying architectures..."
ARCHS=$(lipo -archs "$RELEASE_APP/Contents/MacOS/TopOff")
echo "    Architectures: $ARCHS"
if [[ "$ARCHS" != *"x86_64"* ]] || [[ "$ARCHS" != *"arm64"* ]]; then
    echo "ERROR: Not a universal binary!"
    exit 1
fi

# Re-sign Sparkle's nested helpers with our Developer ID. Sparkle ships
# pre-signed by the Sparkle project, but Apple's notary service requires
# every nested binary to carry OUR Developer ID signature, hardened
# runtime, and a secure timestamp. Sign inside-out: XPC services and
# helpers first, then the framework, then the app itself below.
echo "==> Signing Sparkle framework components..."
SPARKLE_FW="$RELEASE_APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"
# Downloader.xpc keeps its sandbox entitlements (--preserve-metadata)
codesign --force --options runtime --timestamp \
    --preserve-metadata=entitlements \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FW/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FW/Versions/B/Updater.app"
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$SPARKLE_FW"

# Sign the app with hardened runtime and a secure timestamp (required by notary)
echo "==> Signing app with Developer ID..."
codesign --force --options runtime --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$RELEASE_APP"
codesign --verify --strict --verbose=2 "$RELEASE_APP" 2>&1 | tail -3

# Clean up any previous DMG build artifacts
rm -f "$DMG_RW" 2>/dev/null
hdiutil detach "$MOUNT_POINT" 2>/dev/null || true

# Create read-write DMG
echo "==> Creating DMG..."
hdiutil create -size 50m -fs HFS+ -volname "TopOff" "$DMG_RW" > /dev/null 2>&1

# Mount and populate
hdiutil attach "$DMG_RW" -nobrowse > /dev/null 2>&1
cp -R "$RELEASE_APP" "$MOUNT_POINT/"
ln -s /Applications "$MOUNT_POINT/Applications"
mkdir "$MOUNT_POINT/.background"
cp "$BG_IMAGE" "$MOUNT_POINT/.background/background.png"
cp "$VOLUME_ICON" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT"

# Unmount nobrowse, remount for Finder
hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1
hdiutil attach "$DMG_RW" > /dev/null 2>&1

# Set Finder window layout
echo "==> Configuring DMG layout..."
osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "TopOff"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 600, 420}

        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 80
        set background picture of theViewOptions to file ".background:background.png"

        set position of item "TopOff.app" of container window to {105, 170}
        set position of item "Applications" of container window to {395, 170}

        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Reapply the custom volume icon after Finder writes the window metadata.
cp "$VOLUME_ICON" "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a V "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT"

# Convert to compressed read-only DMG
hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1
echo "==> Compressing..."
rm -f "$DMG_FINAL" 2>/dev/null
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_FINAL" > /dev/null 2>&1
rm -f "$DMG_RW"

# Sign the DMG itself so Gatekeeper can verify it as a container
echo "==> Signing DMG..."
codesign --force --sign "$SIGNING_IDENTITY" "$DMG_FINAL"

# Submit to Apple notary service and wait for the result (~2-15 min typical)
echo "==> Submitting to Apple notary service..."
echo "    (Typical turnaround: 2-15 minutes. Apple status: developer.apple.com/system-status)"
xcrun notarytool submit "$DMG_FINAL" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

# Staple the notarization ticket onto the DMG so it works offline
echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_FINAL"

# Verify Gatekeeper will accept it on a fresh download
echo "==> Verifying Gatekeeper acceptance..."
spctl -a -vvv -t install "$DMG_FINAL" 2>&1 | tail -5

# Generate the Sparkle appcast entry for this DMG. Signing uses the
# EdDSA private key in the login Keychain (created by generate_keys).
# The enclosure URL must match where the DMG actually gets uploaded:
# a GitHub release tagged v${VERSION} with the DMG attached.
echo "==> Generating Sparkle appcast..."
SPARKLE_BIN="$(find "$HOME/Library/Developer/Xcode/DerivedData" -type d -path "*artifacts/sparkle/Sparkle/bin" -print -quit 2>/dev/null || true)"
if [ -z "$SPARKLE_BIN" ] || [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "ERROR: Sparkle's generate_appcast not found in DerivedData."
    echo "       Build TopOff once in Xcode so SPM fetches the Sparkle artifacts."
    exit 1
fi

# Stage only this release's DMG so the versioned download-url prefix is
# correct for every item generate_appcast emits.
APPCAST_STAGE="$(mktemp -d /tmp/topoff-appcast.XXXXXX)"
cp "$DMG_FINAL" "$APPCAST_STAGE/"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/ihazgithub/TopOff/releases/download/v${VERSION}/" \
    --link "https://github.com/ihazgithub/TopOff" \
    -o "$SCRIPT_DIR/appcast.xml" \
    "$APPCAST_STAGE"
rm -rf "$APPCAST_STAGE"

echo "==> Done: $DMG_NAME"
echo "    $(du -h "$DMG_FINAL" | cut -f1) compressed"
echo "    appcast.xml updated — to ship this update:"
echo "      1. Create GitHub release tagged v${VERSION} with $DMG_NAME attached"
echo "      2. Commit + push appcast.xml so the feed goes live"

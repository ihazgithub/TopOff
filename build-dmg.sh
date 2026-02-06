#!/bin/bash
set -e

# TopOff DMG Builder
# Usage: ./build-dmg.sh [version]
# Example: ./build-dmg.sh 1.4.2

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/TopOff"
BUILD_DIR="$SCRIPT_DIR/build"
ASSETS_DIR="$BUILD_DIR/dmg-assets"
BG_IMAGE="$ASSETS_DIR/background.png"

# Get version from argument or read from project
if [ -n "$1" ]; then
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

        set position of item "TopOff.app" of container window to {125, 155}
        set position of item "Applications" of container window to {375, 155}

        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

# Convert to compressed read-only DMG
hdiutil detach "$MOUNT_POINT" > /dev/null 2>&1
echo "==> Compressing..."
rm -f "$DMG_FINAL" 2>/dev/null
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_FINAL" > /dev/null 2>&1
rm -f "$DMG_RW"

echo "==> Done: $DMG_NAME"
echo "    $(du -h "$DMG_FINAL" | cut -f1) compressed"

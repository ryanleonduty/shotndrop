#!/usr/bin/env bash
# Build an unsigned ShotNDrop.app and package it into a distributable .dmg.
# Usage: scripts/build-release.sh [version]
#   version defaults to a timestamp; pass e.g. `0.1.0` for a real release.

set -euo pipefail

VERSION="${1:-$(date +%Y%m%d-%H%M%S)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/ShotNDrop.xcarchive"
DMG="$DIST/ShotNDrop-$VERSION.dmg"
STAGE="$BUILD/dmg-stage"

echo "==> Cleaning previous artifacts"
rm -rf "$ARCHIVE" "$STAGE" "$DMG"
mkdir -p "$DIST" "$BUILD"

echo "==> Archiving Release build (unsigned)"
xcodebuild \
    -project "$ROOT/ShotNDrop.xcodeproj" \
    -scheme ShotNDrop \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    archive

APP_SRC="$ARCHIVE/Products/Applications/ShotNDrop.app"
if [[ ! -d "$APP_SRC" ]]; then
    echo "!! Expected app at $APP_SRC — archive did not produce it." >&2
    exit 1
fi

echo "==> Strip quarantine and apply ad-hoc signature"
# Apple Silicon refuses to launch fully unsigned Mach-O binaries (error 163).
# Ad-hoc signing (identity "-") is unauthenticated but satisfies the loader.
xattr -cr "$APP_SRC"
codesign --sign - --deep --force "$APP_SRC"

echo "==> Staging DMG contents"
mkdir -p "$STAGE"
cp -R "$APP_SRC" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating $DMG"
hdiutil create \
    -volname "ShotNDrop $VERSION" \
    -srcfolder "$STAGE" \
    -ov \
    -format UDZO \
    "$DMG" >/dev/null

echo "==> Done"
echo "    App:  $APP_SRC"
echo "    DMG:  $DMG"
du -h "$DMG" | awk '{print "    Size:", $1}'

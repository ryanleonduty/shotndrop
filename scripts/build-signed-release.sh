#!/usr/bin/env bash
# Build a Developer ID-signed, notarized, stapled ShotNDrop release: a .dmg plus
# a signed Sparkle appcast entry. Both the .app and the .dmg are notarized and
# stapled so they validate offline and pass Gatekeeper on a clean machine.
#
# Usage: scripts/build-signed-release.sh <version>          e.g. 0.2.0
#
# Prerequisites (one-time, on the signing machine):
#   * A "Developer ID Application" certificate in the login Keychain
#     (Xcode > Settings > Accounts > Manage Certificates > + ).
#   * A notarytool credential profile named by NOTARY_PROFILE (default
#     "shotndrop-notary"):
#       xcrun notarytool store-credentials shotndrop-notary \
#         --apple-id "<apple id>" --team-id "<team id>"
#
# The signing identity and Team ID are read from the Keychain at run time and
# are never echoed. Override the appcast download location with
# APPCAST_DOWNLOAD_URL_PREFIX if the DMGs are not served from the feed's folder.

set -euo pipefail

VERSION="${1:?usage: build-signed-release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
WORK="$ROOT/build"
ARCHIVE="$WORK/ShotNDrop.xcarchive"
EXPORT="$WORK/export"
APP="$EXPORT/ShotNDrop.app"
STAGE="$WORK/dmg-stage"
DMG="$DIST/ShotNDrop-$VERSION.dmg"
ZIP="$WORK/ShotNDrop-$VERSION.zip"
NOTARY_PROFILE="${NOTARY_PROFILE:-shotndrop-notary}"

# --- Resolve the Developer ID identity + Team ID from the Keychain ------------
# Neither value is printed; only their presence is confirmed.
IDENTITY="$(security find-identity -v -p codesigning \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[A-F0-9]+[[:space:]]+"(.*)"$/\1/')"
if [[ -z "$IDENTITY" ]]; then
    echo "!! No 'Developer ID Application' identity found in the Keychain." >&2
    echo "   Create one in Xcode > Settings > Accounts > Manage Certificates." >&2
    exit 1
fi
TEAM_ID="$(printf '%s' "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/')"
if [[ ! "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "!! Could not parse a Team ID from the signing identity." >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    echo "!! Notary profile '$NOTARY_PROFILE' not found. Create it with:" >&2
    echo "   xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <team>" >&2
    exit 1
fi
echo "==> Using Developer ID Application identity (details hidden)"

# --- Clean --------------------------------------------------------------------
echo "==> Cleaning previous artifacts"
rm -rf "$ARCHIVE" "$EXPORT" "$STAGE" "$ZIP" "$DMG"
mkdir -p "$DIST" "$WORK"

# --- Archive (Developer ID, Hardened Runtime already on in project) -----------
echo "==> Archiving Release build (Developer ID signed)"
xcodebuild archive \
    -project "$ROOT/ShotNDrop.xcodeproj" \
    -scheme ShotNDrop \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    MARKETING_VERSION="$VERSION" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY"

# --- Export a Developer ID-signed .app ----------------------------------------
# The export re-signs every nested component (Sparkle.framework and its
# Installer/Downloader XPC services) with the Developer ID identity while
# preserving each one's entitlements — the correct alternative to `codesign
# --deep`, which strips the XPC entitlements and breaks sandboxed updates.
echo "==> Exporting signed app"
cat > "$WORK/export-options.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>developer-id</string>
	<key>signingStyle</key><string>manual</string>
	<key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$WORK/export-options.plist" \
    -exportPath "$EXPORT"

if [[ ! -d "$APP" ]]; then
    echo "!! Expected app at $APP — export did not produce it." >&2
    exit 1
fi

echo "==> Verifying signature + hardened runtime"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dv --verbose=4 "$APP" 2>&1 | grep -i "flags=.*runtime" \
    || { echo "!! Hardened Runtime not enabled on the app." >&2; exit 1; }

# --- Notarize + staple the app ------------------------------------------------
echo "==> Notarizing app (this waits for Apple)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# --- Package the stapled app into a DMG ---------------------------------------
echo "==> Creating $DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create \
    -volname "ShotNDrop $VERSION" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

# --- Sign + notarize + staple the DMG -----------------------------------------
echo "==> Signing + notarizing DMG"
codesign --sign "$IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Gatekeeper assessment"
spctl --assess --type open --context context:primary-signature -v "$DMG"

# --- Sparkle appcast (EdDSA-signed) -------------------------------------------
echo "==> Generating Sparkle appcast"
DOWNLOAD_URL_PREFIX="${APPCAST_DOWNLOAD_URL_PREFIX:-https://ryanleonduty.github.io/shotndrop/}"
SPARKLE_BIN="${SPARKLE_BIN:-$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/artifacts/sparkle/Sparkle/bin/generate_appcast' 2>/dev/null | head -1)}"
if [[ -z "$SPARKLE_BIN" || ! -x "$SPARKLE_BIN" ]]; then
    echo "!! generate_appcast not found. Resolve packages in Xcode or set SPARKLE_BIN." >&2
    exit 1
fi
"$SPARKLE_BIN" "$DIST" --download-url-prefix "$DOWNLOAD_URL_PREFIX"

echo "==> Done"
echo "    App:     $APP (notarized + stapled)"
echo "    DMG:     $DMG (signed + notarized + stapled)"
du -h "$DMG" | awk '{print "    Size:   ", $1}'
echo "    Appcast: $DIST/appcast.xml"
echo "    Publish the DMG + appcast.xml at: $DOWNLOAD_URL_PREFIX"

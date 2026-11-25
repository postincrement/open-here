#!/bin/bash
# Package a distributable zip, and optionally a DMG.
# Signing and notarisation run only when the corresponding environment variables are set.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CREATE_DMG=0
for arg in "$@"; do
    case "$arg" in
        --dmg) CREATE_DMG=1 ;;
        *)
            echo "error: unknown argument: $arg" >&2
            echo "usage: scripts/package.sh [--dmg]" >&2
            exit 1
            ;;
    esac
done

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    "$ROOT/scripts/build.sh"
fi

APP="$ROOT/build/Open Here.app"
if [[ ! -d "$APP" ]]; then
    echo "error: $APP does not exist. Run scripts/build.sh first." >&2
    exit 1
fi

if [[ -n "${DEVELOPER_ID:-}" ]]; then
    echo "Signing with Developer ID..."
    codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    echo "No DEVELOPER_ID set. Leaving the local signature unchanged."
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DIST="$ROOT/dist"
mkdir -p "$DIST"
ZIP="$DIST/OpenHere-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Created: $ZIP"

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "Submitting for notarisation..."
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "$APP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Notarised and re-zipped: $ZIP"
else
    echo "No NOTARY_KEYCHAIN_PROFILE set. Skipping notarisation."
fi

if [[ "$CREATE_DMG" == "1" ]]; then
    DMG="$DIST/OpenHere-${VERSION}.dmg"
    rm -f "$DMG"
    hdiutil create -volname "Open Here" -srcfolder "$APP" -ov -format UDZO "$DMG"
    if [[ -n "${DEVELOPER_ID:-}" ]]; then
        codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
    fi
    echo "Created: $DMG"
fi

#!/bin/bash
# Build a universal Release copy of Open Here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Generating application icons..."
swift "$ROOT/scripts/generate_icons.swift" "$ROOT"

CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED="$ROOT/build/DerivedData"

echo "Building Open Here (${CONFIGURATION}, arm64 and x86_64)..."
if ! xcodebuild \
    -project "$ROOT/ChromeLauncher.xcodeproj" \
    -scheme ChromeLauncher \
    -configuration "$CONFIGURATION" \
    -destination "platform=macOS" \
    -derivedDataPath "$DERIVED" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
    build
then
    echo "error: xcodebuild failed." >&2
    exit 1
fi

APP="$DERIVED/Build/Products/${CONFIGURATION}/Open Here.app"
if [[ ! -d "$APP" ]]; then
    echo "error: built app not found at: $APP" >&2
    exit 1
fi

OUTPUT="$ROOT/build/Open Here.app"
rm -rf "$OUTPUT"
mkdir -p "$ROOT/build"
cp -R "$APP" "$OUTPUT"

echo "Built: $OUTPUT"
lipo -info "$OUTPUT/Contents/MacOS/Open Here" || true

#!/usr/bin/env bash
# Builds SeeImage.app into build/ without Xcode (SwiftPM + ad-hoc codesign).
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT"
swift build -c "$CONFIG" --product SeeImage

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
APP="$ROOT/build/SeeImage.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN_DIR/SeeImage" "$APP/Contents/MacOS/SeeImage"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"

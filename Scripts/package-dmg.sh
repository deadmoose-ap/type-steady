#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
DIST_DIR="$PROJECT_ROOT/dist"
STAGE_DIR="$DIST_DIR/dmg-stage"
DMG_PATH="$DIST_DIR/TypeSteady-0.1.8-arm64.dmg"

if [[ "${SKIP_APP_BUILD:-0}" != "1" ]]; then
    "$PROJECT_ROOT/Scripts/build-app.sh"
fi
rm -rf "$STAGE_DIR" "$DMG_PATH"
mkdir -p "$STAGE_DIR"
cp -R "$DIST_DIR/TypeSteady.app" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
hdiutil create -volname "TypeSteady" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH"
rm -rf "$STAGE_DIR"
echo "$DMG_PATH"

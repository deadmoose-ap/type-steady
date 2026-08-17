#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_PATH="$PROJECT_ROOT/dist/TypeSteady.app"
DMG_PATH="$PROJECT_ROOT/dist/TypeSteady-0.1.4-arm64.dmg"

if [[ -z "${DEVELOPER_ID_APPLICATION:-}" || -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    echo "Set DEVELOPER_ID_APPLICATION and NOTARY_KEYCHAIN_PROFILE first." >&2
    exit 2
fi

"$PROJECT_ROOT/Scripts/build-app.sh"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" \
    --entitlements "$PROJECT_ROOT/Support/TypeSteady.entitlements" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

SKIP_APP_BUILD=1 "$PROJECT_ROOT/Scripts/package-dmg.sh"
codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

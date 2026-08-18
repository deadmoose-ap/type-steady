#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
cd "$PROJECT_ROOT"

swift test --disable-sandbox
swift run --disable-sandbox TypeSteady --self-test
"$PROJECT_ROOT/Scripts/check-privacy.sh"
"$PROJECT_ROOT/Scripts/build-app.sh"
cmp "$PROJECT_ROOT/Support/AppIcon.icns" \
    "$PROJECT_ROOT/dist/TypeSteady.app/Contents/Resources/TypeSteady.icns"
test -f "$PROJECT_ROOT/dist/TypeSteady.app/Contents/Resources/Assets.car"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$PROJECT_ROOT/dist/TypeSteady.app/Contents/Info.plist")" = "TypeSteady"
xcrun assetutil --info "$PROJECT_ROOT/dist/TypeSteady.app/Contents/Resources/Assets.car" | \
    rg -q '"AssetType" : "IconGroup"'

#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_NAME="TypeSteady"
EXECUTABLE_NAME="TypeSteady"
BUILD_DIR="$PROJECT_ROOT/.build/arm64-apple-macosx/release"
ICON_DOCUMENT="$PROJECT_ROOT/Support/IconSources/IconComposer/TypeSteady.icon"
ICON_BUILD_DIR="$PROJECT_ROOT/.build/icon-assets"
APP_DIR="$PROJECT_ROOT/dist/$APP_NAME.app"

source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
cd "$PROJECT_ROOT"
swift build --disable-sandbox -c release --arch arm64

rm -rf "$APP_DIR" "$ICON_BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$ICON_BUILD_DIR"

# Compile the layered Icon Composer document exactly as Xcode does. Assets.car
# keeps the adaptive Liquid Glass representation, while TypeSteady.icns is the
# system-generated fallback used by macOS 15 and other static icon consumers.
xcrun actool \
    --compile "$ICON_BUILD_DIR" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon "$APP_NAME" \
    --output-partial-info-plist "$ICON_BUILD_DIR/icon-partial.plist" \
    --output-format human-readable-text \
    "$ICON_DOCUMENT"

cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_BUILD_DIR/Assets.car" "$APP_DIR/Contents/Resources/Assets.car"
cp "$ICON_BUILD_DIR/$APP_NAME.icns" "$APP_DIR/Contents/Resources/$APP_NAME.icns"

RESOURCE_BUNDLE="$BUILD_DIR/TypeSteady_TypeSteadyApp.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

# Exercise the packaged bundle rather than the SwiftPM build directory. This
# catches resource lookup regressions that only occur after installation.
"$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME" --self-test

codesign --force --options runtime --timestamp=none --sign - \
    --entitlements "$PROJECT_ROOT/Support/TypeSteady.entitlements" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"

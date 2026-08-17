#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
APP_NAME="TypeSteady"
EXECUTABLE_NAME="TypeSteady"
BUILD_DIR="$PROJECT_ROOT/.build/arm64-apple-macosx/release"
APP_DIR="$PROJECT_ROOT/dist/$APP_NAME.app"

source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
cd "$PROJECT_ROOT"
swift build --disable-sandbox -c release --arch arm64

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$EXECUTABLE_NAME" "$APP_DIR/Contents/MacOS/$EXECUTABLE_NAME"
cp "$PROJECT_ROOT/Support/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT/Support/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

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

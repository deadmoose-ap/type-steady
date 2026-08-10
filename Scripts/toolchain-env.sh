#!/bin/zsh

PROJECT_ROOT="${0:A:h:h}"

if [[ -z "${SDKROOT:-}" ]]; then
    if [[ -d /Applications/Xcode.app ]]; then
        export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
    elif [[ -d /Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk ]]; then
        # Some standalone CLT updates leave MacOSX.sdk newer than their compiler.
        # The 15.4 SDK is sufficient for this app's deployment target.
        export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
    else
        export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
    fi
fi

export SWIFTPM_MODULECACHE_OVERRIDE="$PROJECT_ROOT/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_ROOT/.build/clang-cache"

#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
cd "$PROJECT_ROOT"

FORBIDDEN_PATTERN='URLSession|Network\.framework|import Network|Sparkle|Sentry|Crashlytics|TelemetryClient|NSPasteboard|UIPasteboard'
if rg -n "$FORBIDDEN_PATTERN" Sources Package.swift; then
    echo "Privacy check failed: forbidden API or dependency found." >&2
    exit 1
fi

if rg -n 'logger\.(debug|info|notice|warning|error|critical).*\b(word|text|selection|keyCode)\b' Sources; then
    echo "Privacy check failed: possible text-bearing log call found." >&2
    exit 1
fi

echo "Privacy source check passed."

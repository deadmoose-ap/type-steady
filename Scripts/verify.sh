#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
source "$PROJECT_ROOT/Scripts/toolchain-env.sh"
cd "$PROJECT_ROOT"

swift run --disable-sandbox LangSwitcher --self-test
"$PROJECT_ROOT/Scripts/check-privacy.sh"
"$PROJECT_ROOT/Scripts/build-app.sh"

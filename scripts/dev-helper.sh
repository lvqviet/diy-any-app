#!/bin/zsh
# Builds the Debug helper and runs one of its developer commands as root.
# Output is also written to build/logs/ so it can be inspected later.
#
#   scripts/dev-helper.sh status
#   scripts/dev-helper.sh selftest
#   scripts/dev-helper.sh run --limit 80 [--auto-discharge] [--discharge] [--top-up] [--seconds N]
#   scripts/dev-helper.sh charging on      # recovery
#   scripts/dev-helper.sh adapter on       # recovery
set -euo pipefail

ROOT="${0:A:h:h}"
DERIVED="$ROOT/build/DerivedData"
HELPER="$DERIVED/Build/Products/Debug/DIY Any App.app/Contents/MacOS/DIYAnyAppHelper"
LOG_DIR="$ROOT/build/logs"

if [[ $# -eq 0 ]]; then
  echo "usage: $0 status|selftest|run|charging|adapter [args]"
  exit 64
fi

cd "$ROOT"
if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
  xcodegen generate --quiet
  xcodebuild -project DIYAnyApp.xcodeproj -scheme DIYAnyApp -configuration Debug \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates build | grep -E 'error:|BUILD' || true
fi
[[ -x "$HELPER" ]] || { echo "Helper not built: $HELPER"; exit 1; }

mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/$1-$(date +%Y%m%d-%H%M%S).log"
echo "logging to $LOG"

if [[ "$1" == status ]]; then
  "$HELPER" "$@" 2>&1 | tee "$LOG"
else
  sudo "$HELPER" "$@" 2>&1 | tee "$LOG"
fi

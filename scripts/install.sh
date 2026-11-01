#!/bin/zsh
# Builds a signed Release and installs it to /Applications.
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="DIY Any App.app"
DERIVED="$ROOT/build/DerivedData"
PRODUCT="$DERIVED/Build/Products/Release/$APP_NAME"
DEST="/Applications/$APP_NAME"

cd "$ROOT"
xcodegen generate --quiet
xcodebuild -project DIYAnyApp.xcodeproj -scheme DIYAnyApp -configuration Release \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates build | grep -E 'error:|BUILD' || true
[[ -d "$PRODUCT" ]] || { echo "Build failed"; exit 1; }

# Quitting the app makes the helper restore normal charging.
osascript -e 'tell application id "com.diyanyapp.me" to quit' 2>/dev/null || true
sleep 1

rm -rf "$DEST"
ditto "$PRODUCT" "$DEST"
echo "Installed to $DEST"
open "$DEST"

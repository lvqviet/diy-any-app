#!/bin/zsh
# Builds a signed Release and installs (or updates) it in /Applications.
# The build number is the git commit count, so every update gets a higher one.
# The helper notices its binary changed and restarts itself with the new version.
set -euo pipefail

ROOT="${0:A:h:h}"
APP_NAME="DIY Any App.app"
DERIVED="$ROOT/build/DerivedData"
PRODUCT="$DERIVED/Build/Products/Release/$APP_NAME"
DEST="/Applications/$APP_NAME"

cd "$ROOT"
if [[ -n "$(git status --porcelain)" ]]; then
  echo "warning: uncommitted changes are included in this build"
fi
BUILD_NUMBER="$(git rev-list --count HEAD)"

xcodegen generate --quiet
rm -rf "$PRODUCT"
xcodebuild -project DIYAnyApp.xcodeproj -scheme DIYAnyApp -configuration Release \
  -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build | grep -E 'error:|BUILD' || true
[[ -d "$PRODUCT" ]] || { echo "Build failed"; exit 1; }
VERSION="$(defaults read "$PRODUCT/Contents/Info.plist" CFBundleShortVersionString)"

# Quitting the app makes the helper restore normal charging.
osascript -e 'tell application id "com.diyanyapp.me" to quit' 2>/dev/null || true
sleep 1

rm -rf "$DEST"
ditto "$PRODUCT" "$DEST"
echo "Installed $VERSION ($BUILD_NUMBER) to $DEST"
open "$DEST"

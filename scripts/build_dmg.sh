#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/swichcodex.xcodeproj"
SCHEME="SwichCodex"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="SwichCodex.app"
VOLUME_NAME="${VOLUME_NAME:-SwichCodex}"
FINAL_DMG_NAME="${FINAL_DMG_NAME:-swichcodex-macos.dmg}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME"
STAGING_DIR="$BUILD_ROOT/dmg-staging"
FINAL_DMG_PATH="$DIST_DIR/$FINAL_DMG_NAME"

rm -rf "$STAGING_DIR"
rm -f "$FINAL_DMG_PATH"
mkdir -p "$BUILD_ROOT" "$DIST_DIR" "$STAGING_DIR"

echo "==> Building $SCHEME ($CONFIGURATION)"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -sdk macosx \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build succeeded but app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

echo "==> Preparing DMG staging directory"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating compressed DMG"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$FINAL_DMG_PATH"

echo "DMG created at: $FINAL_DMG_PATH"

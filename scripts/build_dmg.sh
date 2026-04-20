#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/swichcodex.xcodeproj"
SCHEME="SwichCodex"
CONFIGURATION="${CONFIGURATION:-Release}"
BUILD_ROOT="${BUILD_ROOT:-$ROOT_DIR/build}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_NAME="SwichCodex.app"
VOLUME_NAME="${VOLUME_NAME:-SwichCodex}"
ARCHS_TO_BUILD="${ARCHS_TO_BUILD:-arm64 x86_64}"

mkdir -p "$BUILD_ROOT" "$DIST_DIR"
rm -f "$DIST_DIR/swichcodex-macos.dmg"

build_arch() {
  local arch="$1"
  local derived_data_path="$BUILD_ROOT/DerivedData-$arch"
  local app_path="$derived_data_path/Build/Products/$CONFIGURATION/$APP_NAME"
  local staging_dir="$BUILD_ROOT/dmg-staging-$arch"
  local final_dmg_path="$DIST_DIR/swichcodex-macos-$arch.dmg"

  rm -rf "$derived_data_path" "$staging_dir"
  rm -f "$final_dmg_path"
  mkdir -p "$staging_dir"

  echo "==> Building $SCHEME ($CONFIGURATION, $arch)"
  xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$derived_data_path" \
    -sdk macosx \
    -arch "$arch" \
    CODE_SIGNING_ALLOWED=NO \
    ONLY_ACTIVE_ARCH=YES \
    build

  if [[ ! -d "$app_path" ]]; then
    echo "Build succeeded but app bundle was not found at: $app_path" >&2
    exit 1
  fi

  echo "==> Preparing DMG staging directory ($arch)"
  cp -R "$app_path" "$staging_dir/"
  ln -s /Applications "$staging_dir/Applications"

  echo "==> Creating compressed DMG ($arch)"
  hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$staging_dir" \
    -ov \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$final_dmg_path"

  echo "DMG created at: $final_dmg_path"
}

for arch in $ARCHS_TO_BUILD; do
  case "$arch" in
    arm64|x86_64)
      build_arch "$arch"
      ;;
    *)
      echo "Unsupported arch: $arch" >&2
      exit 1
      ;;
  esac
done

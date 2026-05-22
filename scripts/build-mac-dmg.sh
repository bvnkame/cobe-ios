#!/usr/bin/env bash
# Build + ad-hoc sign + package macOS demo as a DMG.
# Usage:
#   scripts/build-mac-dmg.sh [version]
# Output:
#   dist/CobeDemo-<version>.dmg
set -euo pipefail

VERSION="${1:-${GITHUB_REF_NAME:-dev}}"
VERSION="${VERSION#v}"   # strip leading "v" from tag names

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEMO_DIR="$ROOT_DIR/Demo"
BUILD_DIR="$DEMO_DIR/build/mac"
DERIVED_DIR="$BUILD_DIR/DerivedData"
PRODUCTS_DIR="$DERIVED_DIR/Build/Products/Release"
DIST_DIR="$ROOT_DIR/dist"
STAGE_DIR="$BUILD_DIR/dmg-stage"
APP_NAME="CobeDemo"
DMG_NAME="CobeDemo-${VERSION}"
DMG_PATH="$DIST_DIR/${DMG_NAME}.dmg"

echo ">> regenerating xcodeproj"
cd "$DEMO_DIR"
xcodegen generate

echo ">> building $APP_NAME (universal, Release)"
xcodebuild \
  -project "$DEMO_DIR/CobeDemo.xcodeproj" \
  -scheme CobeDemoMac \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DIR" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER:-1}" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$PRODUCTS_DIR/$APP_NAME.app"
if [ ! -d "$APP_PATH" ]; then
  echo "!! app missing at $APP_PATH" >&2
  exit 1
fi

echo ">> ad-hoc signing"
codesign --force --deep --sign - "$APP_PATH"

echo ">> staging DMG layout"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo ">> creating DMG"
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "Cobe Demo $VERSION" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH"

echo ">> done: $DMG_PATH"
ls -lh "$DMG_PATH"

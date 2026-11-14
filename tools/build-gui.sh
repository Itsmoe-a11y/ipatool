#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
OUTPUT=${1:-IPAToolGUI.ipa}

if [ ! -f "$ROOT/ipatool-ios-arm64" ]; then
  "$ROOT/tools/build-ios.sh" "$ROOT/ipatool-ios-arm64"
fi

BUILD_DIR=$(mktemp -d /tmp/ipatool-gui.XXXXXX)
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM

APP_DIR="$BUILD_DIR/Payload/IPATool.app"
mkdir -p "$APP_DIR"

SDKROOT=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos swiftc \
  -target arm64-apple-ios15.0 \
  -sdk "$SDKROOT" \
  -O \
  -framework SwiftUI -framework UIKit -framework Foundation \
  -parse-as-library \
  -o "$APP_DIR/IPATool" \
  "$ROOT/gui/Sources/App.swift" \
  "$ROOT/gui/Sources/Models.swift" \
  "$ROOT/gui/Sources/Runner.swift" \
  "$ROOT/gui/Sources/Views.swift"

cp "$ROOT/gui/Info.plist" "$APP_DIR/Info.plist"
cp "$ROOT/ipatool-ios-arm64" "$APP_DIR/ipatool"
chmod +x "$APP_DIR/IPATool" "$APP_DIR/ipatool"

ldid -S"$ROOT/resources/ios-entitlements.plist" "$APP_DIR/IPATool"
ldid -S"$ROOT/resources/ios-entitlements.plist" "$APP_DIR/ipatool"

cd "$BUILD_DIR"
zip -r9 "$ROOT/$OUTPUT" Payload
echo "Created $OUTPUT successfully!"

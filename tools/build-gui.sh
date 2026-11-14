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
  -Xlinker -rpath -Xlinker /System/Library/Frameworks \
  -Xlinker -rpath -Xlinker /usr/lib/swift \
  -Xlinker -rpath -Xlinker @executable_path/Frameworks \
  -parse-as-library \
  -o "$APP_DIR/IPAToolApp" \
  "$ROOT/gui/Sources/App.swift" \
  "$ROOT/gui/Sources/Models.swift" \
  "$ROOT/gui/Sources/Runner.swift" \
  "$ROOT/gui/Sources/Views.swift"

cp "$ROOT/gui/Info.plist" "$APP_DIR/Info.plist"
cp "$ROOT/ipatool-ios-arm64" "$APP_DIR/ipatool-cli"
chmod +x "$APP_DIR/IPAToolApp" "$APP_DIR/ipatool-cli"

python3 -c "
import zlib, struct
w, h = 180, 180
raw = bytearray()
for y in range(h):
    raw.append(0)
    for x in range(w):
        r = int(15 + 30 * (y / h))
        g = int(120 + 70 * (x / w))
        b = 245
        raw.extend([r, g, b, 255])
def chunk(tag, data):
    return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(bytes(raw))) + chunk(b'IEND', b'')
open('$APP_DIR/AppIcon.png', 'wb').write(png)
open('$APP_DIR/AppIcon60x60@3x.png', 'wb').write(png)
open('$APP_DIR/AppIcon60x60@2x.png', 'wb').write(png)
"

ldid -S"$ROOT/resources/ios-entitlements.plist" "$APP_DIR/IPAToolApp"
ldid -S"$ROOT/resources/ios-entitlements.plist" "$APP_DIR/ipatool-cli"

cd "$BUILD_DIR"
zip -r9 "$ROOT/$OUTPUT" Payload
echo "Created $OUTPUT successfully!"

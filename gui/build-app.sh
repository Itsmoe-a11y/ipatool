#!/usr/bin/env bash
# ==============================================================================
# IPATool iOS GUI - Bulletproof Build & Packaging Pipeline
# Supports XcodeGen (Primary) with automated fallback to swiftc + actool
# Produces both .ipa and .tipa (TrollStore) packages for iOS 15.0+ (arm64)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../go.mod" ]]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# Configuration defaults
OUTPUT_NAME="IPAToolGUI"
OUTPUT_DIR="$SCRIPT_DIR"
BUILD_MODE="auto" # 'auto', 'xcodegen', or 'swiftc'
BACKEND_BIN=""
SOURCES_DIR=""
RESOURCES_DIR=""
VERBOSE=0

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -o, --output-dir DIR      Directory where .ipa and .tipa will be saved (default: .)
  -n, --name NAME           Base filename for output (default: IPAToolGUI)
  -b, --backend FILE        Path to prebuilt ipatool-ios-arm64 executable
  -s, --sources DIR         Directory containing Swift source files
  -r, --resources DIR       Directory containing Info.plist, Assets.xcassets, etc.
  -m, --mode MODE           Build mode: auto (default), xcodegen, or swiftc
  -v, --verbose             Enable verbose command logging
  -h, --help                Show this help message
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -n|--name)
            OUTPUT_NAME="$2"
            shift 2
            ;;
        -b|--backend)
            BACKEND_BIN="$2"
            shift 2
            ;;
        -s|--sources)
            SOURCES_DIR="$2"
            shift 2
            ;;
        -r|--resources)
            RESOURCES_DIR="$2"
            shift 2
            ;;
        -m|--mode)
            BUILD_MODE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            print_usage
            exit 1
            ;;
    esac
done

[[ $VERBOSE -eq 1 ]] && set -x

# Resolve paths
OUTPUT_IPA="$OUTPUT_DIR/${OUTPUT_NAME}.ipa"
OUTPUT_TIPA="$OUTPUT_DIR/${OUTPUT_NAME}.tipa"

# Auto-locate Sources
if [[ -z "$SOURCES_DIR" ]]; then
    if [[ -d "$SCRIPT_DIR/Sources" ]]; then
        SOURCES_DIR="$SCRIPT_DIR/Sources"
    elif [[ -d "$PROJECT_ROOT/gui/Sources" ]]; then
        SOURCES_DIR="$PROJECT_ROOT/gui/Sources"
    elif [[ -d "$PROJECT_ROOT/Sources" ]]; then
        SOURCES_DIR="$PROJECT_ROOT/Sources"
    else
        echo "Error: Cannot locate Sources directory. Specify with -s." >&2
        exit 1
    fi
fi

# Auto-locate Resources
if [[ -z "$RESOURCES_DIR" ]]; then
    if [[ -d "$SCRIPT_DIR/Resources" ]]; then
        RESOURCES_DIR="$SCRIPT_DIR/Resources"
    elif [[ -d "$PROJECT_ROOT/gui/Resources" ]]; then
        RESOURCES_DIR="$PROJECT_ROOT/gui/Resources"
    elif [[ -d "$PROJECT_ROOT/resources" ]]; then
        RESOURCES_DIR="$PROJECT_ROOT/resources"
    else
        echo "Error: Cannot locate Resources directory. Specify with -r." >&2
        exit 1
    fi
fi

INFO_PLIST="$RESOURCES_DIR/Info.plist"
ENTITLEMENTS="$RESOURCES_DIR/entitlements.plist"
if [[ ! -f "$ENTITLEMENTS" && -f "$PROJECT_ROOT/resources/ios-entitlements.plist" ]]; then
    ENTITLEMENTS="$PROJECT_ROOT/resources/ios-entitlements.plist"
fi

echo "================================================================="
echo "  IPATool iOS GUI Packaging Pipeline"
echo "================================================================="
echo "Sources:      $SOURCES_DIR"
echo "Resources:    $RESOURCES_DIR"
echo "Entitlements: $ENTITLEMENTS"
echo "Target:       iOS 15.0+ (arm64)"
echo "Output IPA:   $OUTPUT_IPA"
echo "Output TIPA:  $OUTPUT_TIPA"
echo "================================================================="

# Environment validation
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Warning: Not running on macOS (Darwin). Build tools may not be available." >&2
    if ! command -v xcrun >/dev/null 2>&1; then
        echo "Error: Xcode development tools (xcrun) are required to build iOS apps." >&2
        exit 1
    fi
fi

if ! command -v ldid >/dev/null 2>&1; then
    echo "Error: 'ldid' is required for ad-hoc signing. Install with: brew install ldid" >&2
    exit 1
fi

SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "Using iOS SDK: $SDKROOT"

# Resolve Go CLI helper binary (ipatool-ios-arm64)
if [[ -z "$BACKEND_BIN" ]]; then
    if [[ -f "$SCRIPT_DIR/ipatool-cli" ]]; then
        BACKEND_BIN="$SCRIPT_DIR/ipatool-cli"
    elif [[ -f "$PROJECT_ROOT/ipatool-ios-arm64" ]]; then
        BACKEND_BIN="$PROJECT_ROOT/ipatool-ios-arm64"
    elif [[ -f "$PROJECT_ROOT/tools/build-ios.sh" ]]; then
        echo "==> Building ipatool Go backend for iOS arm64..."
        "$PROJECT_ROOT/tools/build-ios.sh" "$PROJECT_ROOT/ipatool-ios-arm64"
        BACKEND_BIN="$PROJECT_ROOT/ipatool-ios-arm64"
    fi
fi

if [[ -n "$BACKEND_BIN" && -f "$BACKEND_BIN" ]]; then
    echo "Using Backend Binary: $BACKEND_BIN ($(ls -lh "$BACKEND_BIN" | awk '{print $5}'))"
else
    echo "Warning: Prebuilt backend binary not found. A stub or placeholder must be provided." >&2
fi

# Determine build mode
HAS_XCODEGEN=0
if command -v xcodegen >/dev/null 2>&1 && command -v xcodebuild >/dev/null 2>&1; then
    HAS_XCODEGEN=1
fi

ACTUAL_MODE="$BUILD_MODE"
if [[ "$BUILD_MODE" == "auto" ]]; then
    if [[ $HAS_XCODEGEN -eq 1 && -f "$SCRIPT_DIR/project.yml" ]]; then
        ACTUAL_MODE="xcodegen"
    else
        ACTUAL_MODE="swiftc"
    fi
fi

echo "Active Build Mode: $ACTUAL_MODE"

# Create clean temporary build workspace
BUILD_DIR="$(mktemp -d /tmp/ipatool-build.XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT HUP INT TERM

PAYLOAD_DIR="$BUILD_DIR/Payload"
APP_DIR="$PAYLOAD_DIR/IPATool.app"
mkdir -p "$PAYLOAD_DIR"

# ------------------------------------------------------------------------------
# BUILD STEP
# ------------------------------------------------------------------------------
if [[ "$ACTUAL_MODE" == "xcodegen" ]]; then
    echo "==> Generating Xcode project with XcodeGen..."
    (
        cd "$SCRIPT_DIR"
        xcodegen generate --spec project.yml
    )

    echo "==> Compiling IPATool with xcodebuild (Release, iOS Generic)..."
    DERIVED_DATA="$BUILD_DIR/DerivedData"
    xcodebuild build \
        -project "$SCRIPT_DIR/IPATool.xcodeproj" \
        -scheme IPATool \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$DERIVED_DATA" \
        CODE_SIGNING_ALLOWED=NO \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGN_IDENTITY="" \
        ENABLE_BITCODE=NO \
        SWIFT_COMPILATION_MODE=wholemodule

    BUILT_APP="$DERIVED_DATA/Build/Products/Release-iphoneos/IPATool.app"
    if [[ ! -d "$BUILT_APP" ]]; then
        echo "Error: Built app bundle not found at $BUILT_APP" >&2
        exit 1
    fi
    cp -R "$BUILT_APP" "$APP_DIR"

else
    echo "==> Compiling IPATool using direct swiftc + actool pipeline..."
    mkdir -p "$APP_DIR"

    # 1. Compile Asset Catalog
    ASSETS_DIR="$RESOURCES_DIR/Assets.xcassets"
    if [[ -d "$ASSETS_DIR" ]]; then
        echo "  - Compiling Asset Catalog with actool..."
        xcrun actool "$ASSETS_DIR" \
            --compile "$APP_DIR" \
            --platform iphoneos \
            --minimum-deployment-target 15.0 \
            --app-icon AppIcon \
            --output-partial-info-plist "$BUILD_DIR/partial-info.plist" >/dev/null 2>&1 || true
    fi

    # 2. Copy and merge Info.plist
    cp "$INFO_PLIST" "$APP_DIR/Info.plist"

    # 3. Compile Swift sources
    echo "  - Compiling Swift sources with swiftc (target: arm64-apple-ios15.0)..."
    SWIFT_FILES=("$SOURCES_DIR"/*.swift)
    xcrun --sdk iphoneos swiftc \
        -target arm64-apple-ios15.0 \
        -sdk "$SDKROOT" \
        -O \
        -whole-module-optimization \
        -framework SwiftUI -framework UIKit -framework Foundation \
        -Xlinker -rpath -Xlinker /System/Library/Frameworks \
        -Xlinker -rpath -Xlinker /usr/lib/swift \
        -Xlinker -rpath -Xlinker @executable_path/Frameworks \
        -parse-as-library \
        -o "$APP_DIR/IPAToolApp" \
        "${SWIFT_FILES[@]}"

    # 4. PkgInfo
    echo -n "APPL????" > "$APP_DIR/PkgInfo"
fi

# ------------------------------------------------------------------------------
# EMBED SWIFT CONCURRENCY RUNTIME (iOS 15.0+ BACK-DEPLOYMENT)
# ------------------------------------------------------------------------------
DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || echo '/Applications/Xcode.app/Contents/Developer')"
SWIFT_BACKDEPLOY_LIB="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift-5.0/iphoneos"
if [[ -d "$SWIFT_BACKDEPLOY_LIB" ]]; then
    echo "==> Embedding Swift Concurrency back-deployment runtime libraries..."
    mkdir -p "$APP_DIR/Frameworks"
    for lib in libswift_Concurrency.dylib libswift_StringProcessing.dylib; do
        if [[ -f "$SWIFT_BACKDEPLOY_LIB/$lib" ]]; then
            cp "$SWIFT_BACKDEPLOY_LIB/$lib" "$APP_DIR/Frameworks/"
            echo "  - Embedded $lib into Frameworks/"
        fi
    done
fi

# ------------------------------------------------------------------------------
# EMBED HELPER BINARY & ASSETS
# ------------------------------------------------------------------------------
echo "==> Embedding helper CLI and assets..."
if [[ -n "$BACKEND_BIN" && -f "$BACKEND_BIN" ]]; then
    cp "$BACKEND_BIN" "$APP_DIR/ipatool-cli"
    chmod 755 "$APP_DIR/ipatool-cli"
else
    echo "Warning: No backend binary found to embed!" >&2
fi

chmod 755 "$APP_DIR/IPAToolApp"

# Ensure standalone PNG icons are copied as fallback for SpringBoard
if [[ -d "$RESOURCES_DIR/Assets.xcassets/AppIcon.appiconset" ]]; then
    for icon in "$RESOURCES_DIR/Assets.xcassets/AppIcon.appiconset"/*.png; do
        if [[ -f "$icon" ]]; then
            cp "$icon" "$APP_DIR/"
        fi
    done
    [[ -f "$APP_DIR/icon-60@3x.png" ]] && cp "$APP_DIR/icon-60@3x.png" "$APP_DIR/AppIcon.png"
fi

# ------------------------------------------------------------------------------
# CODE SIGNING VIA LDID (TROLLSTORE / JAILBREAK ENTITLEMENTS)
# ------------------------------------------------------------------------------
echo "==> Signing binaries and bundle with ldid..."
if [[ -f "$ENTITLEMENTS" ]]; then
    echo "  - Using entitlements: $ENTITLEMENTS"

    # Sign embedded helper
    if [[ -f "$APP_DIR/ipatool-cli" ]]; then
        ldid -S"$ENTITLEMENTS" "$APP_DIR/ipatool-cli"
    fi

    # Sign embedded dylibs
    if [[ -d "$APP_DIR/Frameworks" ]]; then
        for dylib in "$APP_DIR/Frameworks"/*.dylib; do
            if [[ -f "$dylib" ]]; then
                ldid -S"$ENTITLEMENTS" "$dylib"
            fi
        done
    fi

    # Sign main executable and app bundle
    ldid -S"$ENTITLEMENTS" "$APP_DIR/IPAToolApp"
    ldid -S"$ENTITLEMENTS" "$APP_DIR"
else
    echo "Warning: Entitlements file not found. Performing ad-hoc sign without entitlements." >&2
    ldid -s "$APP_DIR/IPAToolApp"
    [[ -f "$APP_DIR/ipatool-cli" ]] && ldid -s "$APP_DIR/ipatool-cli"
fi

# ------------------------------------------------------------------------------
# PACKAGING (.IPA & .TIPA)
# ------------------------------------------------------------------------------
echo "==> Packaging into .ipa and .tipa..."
mkdir -p "$OUTPUT_DIR"

(
    cd "$BUILD_DIR"
    zip -qr9 "$OUTPUT_IPA" Payload
)

# TrollStore uses .tipa format (exact same payload, dedicated file extension)
cp "$OUTPUT_IPA" "$OUTPUT_TIPA"

# ------------------------------------------------------------------------------
# VERIFICATION & SUMMARY
# ------------------------------------------------------------------------------
echo ""
echo "================================================================="
echo "  Build & Packaging Succeeded!"
echo "================================================================="
echo "IPA package:  $OUTPUT_IPA ($(ls -lh "$OUTPUT_IPA" | awk '{print $5}'))"
echo "TIPA package: $OUTPUT_TIPA ($(ls -lh "$OUTPUT_TIPA" | awk '{print $5}'))"
echo ""
echo "SHA-256 Checksums:"
shasum -a 256 "$OUTPUT_IPA"
shasum -a 256 "$OUTPUT_TIPA"
echo ""
echo "Payload Verification:"
unzip -l "$OUTPUT_IPA" | grep -E "Payload/IPATool.app/(IPAToolApp|ipatool-cli|Info.plist|Assets.car|Frameworks)" || true
echo "================================================================="

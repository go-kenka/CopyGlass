#!/bin/bash

APP_NAME="CopyGlass"
CONFIGURATION="${CONFIGURATION:-debug}"
BUILD_DIR=".build/$CONFIGURATION"
SOURCES_DIR="Sources"
RESOURCES_DIR="$SOURCES_DIR/Resources"
APP_BUNDLE="$APP_NAME.app"

# 1. Build
echo "Building..."
swift build --disable-sandbox -c "$CONFIGURATION"
if [ $? -ne 0 ]; then
    echo "Build failed!"
    exit 1
fi

# 2. Create Structure
echo "Creating App Bundle Structure..."
if [ -d "$APP_BUNDLE" ]; then
    rm -rf "$APP_BUNDLE"
fi

mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy Files
echo "Copying binary..."
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 3.1 Record the real SDK version in the Mach-O metadata.
# SwiftPM links with `-target arm64-apple-macos14.0`, so the linker records 14.0 as the SDK version
# in LC_BUILD_VERSION instead of the SDK the app is actually compiled against. System frameworks
# (SwiftUI included) use the recorded SDK version for "linked on or after" behaviour checks; with
# 14.0 recorded, SwiftUI keeps its legacy window layout: the sidebar toggle is drawn next to the
# traffic lights and the sidebar search field loses its margin to the list below it. Rewrite the
# load command with the real SDK version while keeping macOS 14 as the minimum.
MIN_MACOS="14.0"
SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || true)"
if [ -n "$SDK_VERSION" ] && xcrun -f vtool >/dev/null 2>&1; then
    echo "Recording SDK version $SDK_VERSION (minimum macOS $MIN_MACOS)..."
    if xcrun vtool -set-build-version macos "$MIN_MACOS" "$SDK_VERSION" \
        -replace -output "$APP_BUNDLE/Contents/MacOS/$APP_NAME.sdkfix" \
        "$APP_BUNDLE/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
        mv "$APP_BUNDLE/Contents/MacOS/$APP_NAME.sdkfix" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
    else
        rm -f "$APP_BUNDLE/Contents/MacOS/$APP_NAME.sdkfix"
        echo "warning: could not record the SDK version; the window may keep the legacy layout."
    fi
fi

echo "Copying Info.plist..."
cp "$SOURCES_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# 4. Copy Resources if any (SwiftPM puts them in a bundle usually, but we might need to handle manual resources if any)
# For now, we don't have extra resources folder separate from what SwiftPM handles, 
# but SwiftPM resources are usually embedded or in a separate bundle. 
# Since we used .process("Resources"), SwiftPM creates a CopyGlass_CopyGlass.bundle
if [ -d "$BUILD_DIR/CopyGlass_CopyGlass.bundle" ]; then
    echo "Copying Resources bundle..."
    cp -r "$BUILD_DIR/CopyGlass_CopyGlass.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# 4.1 App Icon (CopyGlass.icns)
ICONSET_DIR="$RESOURCES_DIR/AppIcon.iconset"
ICNS_PATH="$RESOURCES_DIR/CopyGlass.icns"
if [ ! -f "$ICNS_PATH" ]; then
    echo "Generating app icon..."
    swift Tools/GenerateAppIcon.swift
    if [ $? -ne 0 ]; then
        echo "Icon generation failed!"
        exit 1
    fi
    iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
    if [ $? -ne 0 ]; then
        echo "iconutil failed!"
        exit 1
    fi
fi
echo "Copying app icon..."
cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/"

# 5. Permissions
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 6. Ad-hoc code signature
# macOS keys Screen Recording / Accessibility permissions to the app's code signature, so the
# bundle id is pinned as the signing identifier. Note that an ad-hoc signature's designated
# requirement is bound to the cdhash, so re-granting may still be required after a rebuild; a
# stable Developer ID (or self-signed) certificate is needed to keep the grants.
if command -v codesign >/dev/null 2>&1; then
    echo "Signing (ad-hoc)..."
    codesign --force --deep --sign - --identifier com.github.go-kenka.CopyGlass "$APP_BUNDLE"
fi

echo "Done! $APP_BUNDLE created successfully."

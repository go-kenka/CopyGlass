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

echo "Done! $APP_BUNDLE created successfully."

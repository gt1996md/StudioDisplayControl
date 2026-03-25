#!/bin/bash
# build_app.sh — Compile and package as a macOS .app bundle with icon
# Usage: chmod +x build_app.sh && ./build_app.sh

set -e

APP_NAME="StudioDisplayControl"
BUNDLE_ID="com.studiodisplay.control"
APP_DIR="${APP_NAME}.app"

echo "Building ${APP_NAME}..."
swiftc -O \
    -framework CoreAudio \
    -framework AppKit \
    -framework Carbon \
    -framework IOKit \
    -F /System/Library/PrivateFrameworks \
    -framework DisplayServices \
    ${APP_NAME}.swift \
    -o ${APP_NAME}

echo "Creating app icon..."

ICONSET="${APP_NAME}.iconset"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

if [ -f "AppIcon.png" ]; then
    sips -z 16 16     AppIcon.png --out "${ICONSET}/icon_16x16.png"      > /dev/null 2>&1
    sips -z 32 32     AppIcon.png --out "${ICONSET}/icon_16x16@2x.png"   > /dev/null 2>&1
    sips -z 32 32     AppIcon.png --out "${ICONSET}/icon_32x32.png"      > /dev/null 2>&1
    sips -z 64 64     AppIcon.png --out "${ICONSET}/icon_32x32@2x.png"   > /dev/null 2>&1
    sips -z 128 128   AppIcon.png --out "${ICONSET}/icon_128x128.png"    > /dev/null 2>&1
    sips -z 256 256   AppIcon.png --out "${ICONSET}/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   AppIcon.png --out "${ICONSET}/icon_256x256.png"    > /dev/null 2>&1
    sips -z 512 512   AppIcon.png --out "${ICONSET}/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   AppIcon.png --out "${ICONSET}/icon_512x512.png"    > /dev/null 2>&1
    sips -z 1024 1024 AppIcon.png --out "${ICONSET}/icon_512x512@2x.png" > /dev/null 2>&1

    iconutil -c icns "${ICONSET}" -o AppIcon.icns
    rm -rf "${ICONSET}"
    echo "App icon created."
else
    echo "Warning: AppIcon.png not found, building without icon."
fi

echo "Packaging ${APP_DIR}..."

rm -rf "${APP_DIR}"

mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP_DIR}/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Studio Display Control</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

rm -f "${APP_NAME}"

echo ""
echo "Done! ${APP_DIR} is ready."
echo ""
echo "Next steps:"
echo ""
echo "  1. Move to Applications:"
echo "     cp -r ${APP_DIR} /Applications/"
echo ""
echo "  2. First launch — right-click the app > Open > Open again"
echo ""
echo "  3. Grant Accessibility permission:"
echo "     System Settings > Privacy & Security > Accessibility"
echo ""
echo "  4. (Optional) Launch at login:"
echo "     System Settings > General > Login Items"

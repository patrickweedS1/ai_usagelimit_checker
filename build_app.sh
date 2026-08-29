#!/bin/bash
set -e

APP_NAME="Neurolytics"
OUTPUT_DIR="build"
APP_DIR="${OUTPUT_DIR}/${APP_NAME}.app"

echo "Creating macOS app bundle structure for ${APP_NAME}..."
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"
mkdir -p "${APP_DIR}/Contents/PlugIns/NeurolyticsWidget.appex/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/PlugIns/NeurolyticsWidget.appex/Contents/Resources"

# Generate Info.plist for Main App
echo "Generating Info.plist..."
cat << 'EOF' > "${APP_DIR}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Neurolytics</string>
    <key>CFBundleIdentifier</key>
    <string>com.patrickweed.neurolytics</string>
    <key>CFBundleName</key>
    <string>Neurolytics</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Generate Info.plist for Widget Extension
echo "Generating Widget Info.plist..."
cat << 'EOF' > "${APP_DIR}/Contents/PlugIns/NeurolyticsWidget.appex/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>NeurolyticsWidget</string>
    <key>CFBundleIdentifier</key>
    <string>com.patrickweed.neurolytics.widget</string>
    <key>CFBundleName</key>
    <string>NeurolyticsWidget</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.widgetkit-extension</string>
        <key>NSExtensionPrincipalClass</key>
        <string>_TtC18NeurolyticsWidget18NeurolyticsWidget</string>
    </dict>
</dict>
</plist>
EOF

if [ -f "AppIcon.icns" ]; then
    echo "Bundling App Icon..."
    cp "AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
    cp "AppIcon.icns" "${APP_DIR}/Contents/PlugIns/NeurolyticsWidget.appex/Contents/Resources/AppIcon.icns"
else
    echo "WARNING: AppIcon.icns not found! Proceeding with generic icon."
fi

echo "Compiling SwiftUI App sources with swiftc..."
swiftc -parse-as-library \
    -O \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macos14.0 \
    -o "${APP_DIR}/Contents/MacOS/Neurolytics" \
    NeurolyticsApp.swift \
    ContentView.swift \
    SettingsView.swift \
    QuotaModels.swift \
    KeychainHelper.swift \
    APIClients.swift \
    QuotaManager.swift \
    OAuthHelper.swift

echo "Compiling WidgetKit Extension with swiftc..."
swiftc -parse-as-library \
    -O \
    -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
    -target arm64-apple-macos14.0 \
    -o "${APP_DIR}/Contents/PlugIns/NeurolyticsWidget.appex/Contents/MacOS/NeurolyticsWidget" \
    NeurolyticsWidget.swift \
    QuotaModels.swift

echo "Making executable..."
chmod +x "${APP_DIR}/Contents/MacOS/Neurolytics"
chmod +x "${APP_DIR}/Contents/PlugIns/NeurolyticsWidget.appex/Contents/MacOS/NeurolyticsWidget"

echo "============================================="
echo "SUCCESS! macOS App successfully created at:"
echo "$(pwd)/${APP_DIR}"
echo "============================================="

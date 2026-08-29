#!/bin/bash
set -e

APP_NAME="Neurolytics"
OUTPUT_DIR="build"
APP_PATH="${OUTPUT_DIR}/${APP_NAME}.app"
ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}.zip"

echo "Step 1: Compiling the application..."
if [ -f "./build_app.sh" ]; then
    ./build_app.sh
else
    echo "ERROR: build_app.sh not found!"
    exit 1
fi

echo ""
echo "Step 2: Applying ad-hoc code signature..."
# Modern macOS requires all executables and app extensions to have at least an ad-hoc signature to launch/register.
# App Extensions (like WidgetKit) MUST be sandboxed on modern macOS (Sonoma/Sequoia), so we sign them with the sandbox entitlement.
# We sign from the inside out (first the widget extension, then the main app bundle).

WIDGET_PATH="${APP_PATH}/Contents/Extensions/NeurolyticsWidget.appex"
echo "Signing Widget Extension with Sandbox Entitlements and Hardened Runtime..."
codesign --force --options runtime --sign - --entitlements NeurolyticsWidget.entitlements "${WIDGET_PATH}"

echo "Signing Main App Bundle with Hardened Runtime and App Group Entitlements..."
codesign --force --options runtime --sign - --entitlements Neurolytics.entitlements "${APP_PATH}"

echo ""
echo "Step 3: Creating a distribution zip using ditto..."
# ditto is preferred over zip because it preserves resource forks, permissions, and symlinks.
if [ -f "${ZIP_PATH}" ]; then
    rm "${ZIP_PATH}"
fi
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo ""
echo "============================================="
echo "SUCCESS! Distribution package created!"
echo "App bundle: ${APP_PATH}"
echo "Zip archive: ${ZIP_PATH}"
echo "============================================="
echo "To share this app:"
echo "1. Host the '${ZIP_PATH}' and the 'install.sh' script online."
echo "2. For example, upload them to a GitHub release, an S3 bucket, or your website."
echo "3. Share the install.sh command with others to install without Gatekeeper quarantine!"
echo "============================================="

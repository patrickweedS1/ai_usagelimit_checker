#!/bin/bash
#
# 🧠 Neurolytics Installer Script
#
# This script downloads, extracts, and installs Neurolytics.app on macOS
# without triggering Gatekeeper quarantine (since curl downloads do not get
# tagged with the com.apple.quarantine attribute).
#
set -e

# ==========================================
# CONFIGURATION
# Set this to the URL where you host Neurolytics.zip (e.g., GitHub Release asset)
DEFAULT_DOWNLOAD_URL="https://github.com/YOUR_GITHUB_USERNAME/ai_usagelimit_checker/releases/latest/download/Neurolytics.zip"
# ==========================================

DOWNLOAD_URL="${NEUROLYTICS_ZIP_URL:-$DEFAULT_DOWNLOAD_URL}"
APP_NAME="Neurolytics"
TARGET_DIR="/Applications"

echo "=========================================================="
echo "      🧠 Welcome to the Neurolytics Installer 🧠"
echo "=========================================================="

# Check if running on macOS
if [ "$(uname)" != "Darwin" ]; then
    echo "ERROR: This installer is only compatible with macOS."
    exit 1
fi

# Check macOS version (minimum macOS 14.0 Sonoma)
OS_VERSION=$(sw_vers -productVersion)
OS_MAJOR=$(echo "$OS_VERSION" | cut -d. -f1)
if [ "$OS_MAJOR" -lt 14 ]; then
    echo "WARNING: Neurolytics requires macOS 14.0 (Sonoma) or newer."
    echo "Your current version is macOS $OS_VERSION."
    read -p "Do you want to attempt installation anyway? (y/N) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation aborted."
        exit 1
    fi
fi

# Check if Neurolytics is currently running and terminate if necessary
if pgrep -x "${APP_NAME}" > /dev/null; then
    echo "Notice: ${APP_NAME} is currently running."
    echo "Closing the app to allow the upgrade..."
    killall "${APP_NAME}" || true
    sleep 1
fi

# Determine target directory
if [ -w "${TARGET_DIR}" ]; then
    INSTALL_PATH="${TARGET_DIR}/${APP_NAME}.app"
else
    echo "Notice: You do not have write permissions to ${TARGET_DIR}."
    echo "Installing to your user-specific Applications directory instead..."
    TARGET_DIR="${HOME}/Applications"
    mkdir -p "${TARGET_DIR}"
    INSTALL_PATH="${TARGET_DIR}/${APP_NAME}.app"
fi

echo "Installing to: ${INSTALL_PATH}"

# Create secure temporary directory
TEMP_DIR=$(mktemp -d -t neurolytics-install-XXXXXX)
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "Downloading ${APP_NAME}..."
if [ "$DOWNLOAD_URL" = "https://github.com/YOUR_GITHUB_USERNAME/ai_usagelimit_checker/releases/latest/download/Neurolytics.zip" ]; then
    echo "----------------------------------------------------------"
    echo "NOTE: This installer is currently configured with a placeholder URL."
    echo "To test this installer locally with your built package, run:"
    echo "  NEUROLYTICS_ZIP_URL=\"file://$(pwd)/build/Neurolytics.zip\" bash install.sh"
    echo "----------------------------------------------------------"
    echo ""
fi

# Download Zip
ZIP_FILE="${TEMP_DIR}/${APP_NAME}.zip"
if [[ "$DOWNLOAD_URL" =~ ^file:// ]]; then
    # Local file installation for testing
    FILE_PATH="${DOWNLOAD_URL#file://}"
    cp "$FILE_PATH" "$ZIP_FILE"
else
    # Remote download using curl
    if ! curl -L -f -o "$ZIP_FILE" "$DOWNLOAD_URL"; then
        echo "ERROR: Failed to download from URL: $DOWNLOAD_URL"
        echo "Please verify the URL is correct and you have an active internet connection."
        exit 1
    fi
fi

echo "Extracting application..."
# Unzip to temporary location
unzip -q "$ZIP_FILE" -d "$TEMP_DIR"

EXTRACTED_APP="${TEMP_DIR}/${APP_NAME}.app"
if [ ! -d "${EXTRACTED_APP}" ]; then
    # Sometimes zip structure might nest the app bundle or have a different name
    # Search for any .app bundle inside the extracted contents
    FOUND_APP=$(find "$TEMP_DIR" -maxdepth 2 -name "*.app" -print -quit)
    if [ -n "$FOUND_APP" ]; then
        EXTRACTED_APP="$FOUND_APP"
    else
        echo "ERROR: Could not find ${APP_NAME}.app in the downloaded archive."
        exit 1
    fi
fi

# Remove existing installation to prevent merge conflicts/corruption
if [ -d "${INSTALL_PATH}" ]; then
    echo "Removing previous version of ${APP_NAME}..."
    rm -rf "${INSTALL_PATH}"
fi

echo "Moving ${APP_NAME} into place..."
mv "${EXTRACTED_APP}" "${INSTALL_PATH}"

# Ensure correct execution permissions
chmod -R +rX "${INSTALL_PATH}"
chmod +x "${INSTALL_PATH}/Contents/MacOS/${APP_NAME}"
if [ -d "${INSTALL_PATH}/Contents/PlugIns/NeurolyticsWidget.appex" ]; then
    chmod +x "${INSTALL_PATH}/Contents/PlugIns/NeurolyticsWidget.appex/Contents/MacOS/NeurolyticsWidget"
fi

# Double check and remove any accidental quarantine flags if they exist
# (Sometimes browsers do weird things, so as a safety net we run xattr)
if command -v xattr >/dev/null 2>&1; then
    xattr -rd com.apple.quarantine "${INSTALL_PATH}" >/dev/null 2>&1 || true
fi

echo ""
echo "=========================================================="
echo "🎉 SUCCESS! ${APP_NAME} has been successfully installed! 🎉"
echo "=========================================================="
echo "You can find the app at:"
echo "  ${INSTALL_PATH}"
echo ""
echo "Since it was installed via curl, you can double-click and"
echo "launch it immediately. No command line actions required!"
echo "=========================================================="
echo ""

# Ask to launch the app now
read -p "Would you like to launch ${APP_NAME} now? (y/N) " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open "${INSTALL_PATH}"
fi

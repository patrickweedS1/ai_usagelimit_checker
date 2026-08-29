#!/bin/bash
set -e

SOURCE_IMAGE="/Users/patrick.weed/Downloads/Gemini_Generated_Image_6h103k6h103k6h10.jpeg"
ICONSET_DIR="AppIcon.iconset"
OUTPUT_ICNS="AppIcon.icns"

if [ ! -f "$SOURCE_IMAGE" ]; then
    echo "ERROR: Source image not found at $SOURCE_IMAGE"
    exit 1
fi

echo "Cleaning up any old assets..."
rm -rf "$ICONSET_DIR" "$OUTPUT_ICNS"
mkdir -p "$ICONSET_DIR"

echo "Resizing assets to standard Apple specifications using sips..."
sips -s format png -z 16 16     "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
sips -s format png -z 32 32     "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
sips -s format png -z 32 32     "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
sips -s format png -z 64 64     "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
sips -s format png -z 128 128   "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
sips -s format png -z 256 256   "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
sips -s format png -z 256 256   "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
sips -s format png -z 512 512   "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
sips -s format png -z 512 512   "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
sips -s format png -z 1024 1024 "$SOURCE_IMAGE" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null

echo "Compiling iconset into native macOS AppIcon.icns format using iconutil..."
iconutil -c icns "$ICONSET_DIR"

echo "Cleaning up temporary iconset directory..."
rm -rf "$ICONSET_DIR"

echo "SUCCESS! Generated macOS app icon at $(pwd)/$OUTPUT_ICNS"

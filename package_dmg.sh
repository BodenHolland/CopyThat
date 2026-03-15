#!/bin/bash

# Exit on error
set -e

PROJECT_NAME="LinkKey"
SCHEME_NAME="LinkKey"
CONFIGURATION="Release"
DMG_NAME="LinkKey.dmg"
BUILD_DIR="build_release"
APP_NAME="${PROJECT_NAME}.app"

echo "🚀 Starting build and DMG packaging process..."

# 1. Clean and Build the app
echo "🔨 Building project in ${CONFIGURATION} mode..."
xcodebuild -scheme "${SCHEME_NAME}" \
           -configuration "${CONFIGURATION}" \
           -derivedDataPath "${BUILD_DIR}" \
           build

# 2. Prepare the DMG staging area
STAGING_DIR="dmg_staging"
echo "📂 Preparing staging directory: ${STAGING_DIR}"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

# Find the built .app
BUILT_APP_PATH=$(find "${BUILD_DIR}/Build/Products/${CONFIGURATION}" -name "${APP_NAME}" -type d -maxdepth 2)

if [ -z "$BUILT_APP_PATH" ]; then
    echo "❌ Error: Could not find ${APP_NAME} in build output."
    exit 1
fi

echo "📦 Copying ${APP_NAME} to staging..."
cp -R "${BUILT_APP_PATH}" "${STAGING_DIR}/"

# 3. Create the Applications shortcut
echo "🔗 Creating Applications folder shortcut..."
ln -s /Applications "${STAGING_DIR}/Applications"

# 4. Create the DMG
echo "💿 Creating DMG..."
rm -f "${DMG_NAME}"
hdiutil create -volname "${PROJECT_NAME}" \
               -srcfolder "${STAGING_DIR}" \
               -ov \
               -format UDZO \
               "${DMG_NAME}"

# 5. Cleanup staging
echo "🧹 Cleaning up staging files..."
rm -rf "${STAGING_DIR}"

echo "✅ Success! Your DMG is ready: ${DMG_NAME}"

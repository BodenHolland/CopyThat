#!/bin/bash

# LinkKey Clean Start Script
# This script kills any running instances of LinkKey, resets permissions, and relaunches the app.

APP_BUNDLE_ID="com.linkkey.app.boden"
APP_PATH="/Applications/LinkKey.app"

echo "🛑 Killing any running instances of LinkKey..."
pkill -f "LinkKey" || true

echo "🧹 Resetting Accessibility permissions..."
tccutil reset Accessibility $APP_BUNDLE_ID

echo "🧹 Resetting Full Disk Access permissions..."
tccutil reset SystemPolicyAllFiles $APP_BUNDLE_ID

echo "🚀 Relaunching LinkKey from $APP_PATH..."
if [ -d "$APP_PATH" ]; then
    open "$APP_PATH"
    echo "✅ LinkKey has been relaunched. Please check your screen for the onboarding/permission window."
else
    echo "❌ Error: Could not find LinkKey.app in /Applications. Please make sure you've installed it first."
fi

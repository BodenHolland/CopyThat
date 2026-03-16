#!/bin/bash

# CopyThat Clean Start Script
# This script kills any running instances of CopyThat, resets permissions, and relaunches the app.

APP_BUNDLE_ID="com.copythat.app.boden"
APP_PATH="/Applications/CopyThat.app"

echo "🛑 Killing any running instances of CopyThat..."
pkill -f "CopyThat" || true

echo "🧹 Resetting Privacy permissions..."
tccutil reset Accessibility $APP_BUNDLE_ID
tccutil reset SystemPolicyAllFiles $APP_BUNDLE_ID

echo "🧹 Clearing App Settings (UserDefaults)..."
defaults delete $APP_BUNDLE_ID || true

echo "🚀 Relaunching CopyThat from $APP_PATH..."
if [ -d "$APP_PATH" ]; then
    open "$APP_PATH"
    echo "✅ CopyThat has been relaunched. Please check your screen for the onboarding/permission window."
else
    echo "❌ Error: Could not find CopyThat.app in /Applications. Please make sure you've installed it first."
fi

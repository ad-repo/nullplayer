#!/bin/bash
# AdAmp Build and Run Script
# Kills any running instance, builds, and runs the app

set -e

cd "$(dirname "$0")/.."

echo "🔄 Stopping any running AdAmp instances..."
pkill -f AdAmp 2>/dev/null || true
sleep 0.5

echo "🔨 Building AdAmp..."
swift build

echo "🚀 Launching AdAmp..."
.build/debug/AdAmp &

echo "✅ AdAmp is running!"

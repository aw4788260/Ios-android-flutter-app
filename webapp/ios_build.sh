#!/bin/bash

# ========================================
# Amr AI - Medaad iOS Build Script
# Contact: 01090991769
# ========================================

set -e

echo "🚀 Starting Medaad iOS Build Process..."
echo "=========================================="

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}❌ Error: This script must run on macOS!${NC}"
    echo "Please transfer the project to a Mac to build iOS version."
    exit 1
fi

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo -e "${RED}❌ Flutter is not installed!${NC}"
    echo "Please install Flutter from https://flutter.dev"
    exit 1
fi

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}❌ Xcode is not installed!${NC}"
    echo "Please install Xcode from App Store"
    exit 1
fi

# Check if CocoaPods is installed
if ! command -v pod &> /dev/null; then
    echo -e "${YELLOW}⚠️  CocoaPods not found. Installing...${NC}"
    sudo gem install cocoapods
fi

echo -e "${GREEN}✅ All prerequisites are installed${NC}"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
flutter clean
rm -rf ios/Pods
rm -rf ios/Podfile.lock

# Get dependencies
echo "📦 Getting Flutter dependencies..."
flutter pub get

# Install iOS pods
echo "📦 Installing iOS pods..."
cd ios
pod install
cd ..

# Check Flutter doctor
echo "🔍 Running Flutter doctor..."
flutter doctor -v

echo ""
echo "=========================================="
echo "✅ Project is ready for iOS build!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Open Xcode: open ios/Runner.xcworkspace"
echo "2. Select a development team in Signing & Capabilities"
echo "3. Connect an iOS device or start a simulator"
echo "4. Build and run from Xcode (Cmd + R)"
echo ""
echo "For App Store release:"
echo "1. Product → Archive"
echo "2. Distribute App → App Store Connect"
echo "3. Upload and wait for processing"
echo ""
echo "📞 Need help? Contact: 01090991769"
echo "🏢 Amr AI Technical Team"
echo ""

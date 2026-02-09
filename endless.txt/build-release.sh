#!/bin/bash
set -e

# endless.txt - Developer ID Release Build Script
# This script builds, signs, and optionally notarizes the app for distribution

# Configuration
APP_NAME="endless.txt"
XCODE_SCHEME="NvrEndingTxt"
DEVELOPER_ID="Developer ID Application: Jun Hao Lim (454K5WYH9Y)"
BUNDLE_ID="com.nvr.NvrEndingTxt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  $APP_NAME - Developer ID Release Build${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Step 0: Check keychain access
echo -e "\n${YELLOW}[0/10] Checking keychain access for code signing...${NC}"
if ! security find-identity -v -p codesigning | grep -q "Developer ID"; then
    echo -e "${RED}Error: Developer ID certificate not found in keychain${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Developer ID certificate found${NC}"
echo -e "${YELLOW}Note: If signing fails, open Keychain Access and ensure your keychain is unlocked${NC}"

# Step 1: Clean previous builds
echo -e "\n${YELLOW}[1/10] Cleaning previous builds...${NC}"
rm -rf ~/Library/Developer/Xcode/DerivedData/NvrEndingTxt-*
rm -rf dist build
echo -e "${GREEN}✓ Clean complete${NC}"

# Step 2: Regenerate Xcode project
echo -e "\n${YELLOW}[2/10] Regenerating Xcode project...${NC}"
xcodegen generate

# Fix Info.plist - xcodegen overwrites version variables with hardcoded "1.0"/"1"
# Restore build variable references so xcodebuild substitutes from project.yml settings
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString '\$(MARKETING_VERSION)'" NvrEndingTxt/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion '\$(CURRENT_PROJECT_VERSION)'" NvrEndingTxt/Info.plist

echo -e "${GREEN}✓ Project regenerated (Info.plist version variables fixed)${NC}"

# Step 3: Build release configuration (without code signing)
echo -e "\n${YELLOW}[3/10] Building release configuration...${NC}"
xcodebuild \
    -project NvrEndingTxt.xcodeproj \
    -scheme "$XCODE_SCHEME" \
    -configuration Release \
    -derivedDataPath ./build \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    build

echo -e "${GREEN}✓ Build complete${NC}"

# Step 4: Copy to dist folder and verify version
echo -e "\n${YELLOW}[4/10] Copying to dist folder and verifying version...${NC}"
BUILD_DIR="./build/Build/Products/Release"
mkdir -p dist
cp -R "$BUILD_DIR/NvrEndingTxt.app" dist/

# CRITICAL: Verify the built app has the correct version from project.yml
# xcodegen can overwrite Info.plist with hardcoded "1.0"/"1" - catch that here
EXPECTED_VERSION=$(grep 'MARKETING_VERSION:' project.yml | awk '{print $2}' | tr -d '"')
EXPECTED_BUILD=$(grep 'CURRENT_PROJECT_VERSION:' project.yml | awk '{print $2}' | tr -d '"')
ACTUAL_VERSION=$(/usr/bin/defaults read "$(pwd)/dist/NvrEndingTxt.app/Contents/Info.plist" CFBundleShortVersionString)
ACTUAL_BUILD=$(/usr/bin/defaults read "$(pwd)/dist/NvrEndingTxt.app/Contents/Info.plist" CFBundleVersion)

if [ "$ACTUAL_VERSION" != "$EXPECTED_VERSION" ] || [ "$ACTUAL_BUILD" != "$EXPECTED_BUILD" ]; then
    echo -e "${RED}ERROR: Version mismatch!${NC}"
    echo -e "${RED}  Expected: $EXPECTED_VERSION (build $EXPECTED_BUILD)${NC}"
    echo -e "${RED}  Actual:   $ACTUAL_VERSION (build $ACTUAL_BUILD)${NC}"
    echo -e "${RED}  This usually means xcodegen overwrote Info.plist version variables.${NC}"
    echo -e "${RED}  Check that Info.plist uses \$(MARKETING_VERSION) and \$(CURRENT_PROJECT_VERSION).${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Version verified: $ACTUAL_VERSION (build $ACTUAL_BUILD)${NC}"

# Step 5: Sign with Developer ID
echo -e "\n${YELLOW}[5/10] Signing with Developer ID...${NC}"
cd dist

# Remove extended attributes that might interfere
xattr -cr NvrEndingTxt.app

# Deep sign entire bundle including Sparkle framework.
# xcodebuild strips Sparkle's header files during copy, breaking its original seal.
# --deep re-signs all nested code (Sparkle, XPC services, Updater) with our Developer ID.
echo "Signing entire app bundle with Developer ID (deep)..."
codesign --force --deep --sign "$DEVELOPER_ID" \
    --options runtime \
    --timestamp \
    --entitlements ../NvrEndingTxt/NvrEndingTxt.entitlements \
    NvrEndingTxt.app

echo -e "${GREEN}✓ Signing complete${NC}"

# Step 6: Verify code signature
echo -e "\n${YELLOW}[6/8] Verifying code signature...${NC}"
codesign --verify --deep --strict --verbose=2 NvrEndingTxt.app
echo -e "${GREEN}✓ Code signature valid${NC}"

# Step 7: Rename to endless.txt.app
echo -e "\n${YELLOW}[7/8] Renaming to $APP_NAME.app...${NC}"
cp -R NvrEndingTxt.app "$APP_NAME.app"
echo -e "${GREEN}✓ Rename complete${NC}"

# Step 8: Notarization (optional but recommended)
echo -e "\n${YELLOW}[8/9] Notarization...${NC}"
read -p "Do you want to notarize the app? (requires Apple ID app-specific password) [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Create a ZIP for notarization (faster than DMG)
    echo "Creating archive for notarization..."
    ditto -c -k --keepParent "$APP_NAME.app" "$APP_NAME.zip"

    echo "Submitting for notarization..."
    echo "You'll need to provide your Apple ID and app-specific password"
    read -p "Apple ID: " APPLE_ID
    read -p "Team ID (454K5WYH9Y): " TEAM_ID
    TEAM_ID=${TEAM_ID:-454K5WYH9Y}

    xcrun notarytool submit "$APP_NAME.zip" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --wait

    # Staple the notarization ticket
    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_NAME.app"

    # Clean up ZIP
    rm "$APP_NAME.zip"

    echo -e "${GREEN}✓ Notarization complete${NC}"
else
    echo -e "${YELLOW}⚠ Skipping notarization - users will see Gatekeeper warnings${NC}"
fi

# Step 9: Create DMG
echo -e "\n${YELLOW}[9/10] Creating DMG...${NC}"
mkdir -p dmg_contents
cp -R "$APP_NAME.app" dmg_contents/
ln -sf /Applications dmg_contents/Applications

hdiutil create -volname "$APP_NAME" -srcfolder dmg_contents -ov -format UDZO "$APP_NAME.dmg"
rm -rf dmg_contents

echo -e "${GREEN}✓ DMG created${NC}"

# Step 10: Sign DMG for Sparkle updates
echo -e "\n${YELLOW}[10/10] Signing DMG for Sparkle...${NC}"
SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/Sparkle*/Build/Products/*" 2>/dev/null | head -1)

if [ -z "$SIGN_TOOL" ]; then
    # Try build directory
    SIGN_TOOL=$(find ./build -name "sign_update" -path "*/Sparkle*" 2>/dev/null | head -1)
fi

if [ -n "$SIGN_TOOL" ]; then
    echo "Using sign_update: $SIGN_TOOL"
    DMG_SIZE=$(stat -f%z "$APP_NAME.dmg")
    SIGNATURE=$("$SIGN_TOOL" "$APP_NAME.dmg")

    echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Release Information for appcast.xml${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}DMG Size:${NC} $DMG_SIZE bytes"
    echo -e "${YELLOW}Signature:${NC} $SIGNATURE"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}⚠ Could not find sign_update tool${NC}"
    echo "You'll need to manually sign the DMG for Sparkle updates"
fi

echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✓ Build Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "\n${YELLOW}Output files:${NC}"
echo -e "  • dist/$APP_NAME.app (signed with Developer ID)"
echo -e "  • dist/$APP_NAME.dmg (ready for distribution)"
echo -e "\n${YELLOW}Next steps:${NC}"
echo -e "  1. Update appcast.xml with signature and file size"
echo -e "  2. Test the app on a clean Mac"
echo -e "  3. Create GitHub release and upload DMG"
echo ""

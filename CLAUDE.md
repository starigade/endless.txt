# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Generate Xcode project (required before first build)
cd endless.txt && xcodegen generate

# Open in Xcode
open endless.txt/NvrEndingTxt.xcodeproj

# Build from command line
xcodebuild -project endless.txt/NvrEndingTxt.xcodeproj -scheme NvrEndingTxt -configuration Debug build
```

**Prerequisites:** `brew install xcodegen`

## Architecture

This is a macOS menu bar app (no dock icon) for quick thought capture to a single text file.

### Key Components

- **AppDelegate** (`AppDelegate.swift`) - Central coordinator managing menu bar status item, floating panel lifecycle, and global hotkey registration. Implements `NSWindowDelegate` for window frame persistence.

- **FloatingPanel** (`Views/FloatingPanel.swift`) - Custom `NSPanel` subclass that enables keyboard input on a borderless window. Required because standard `NSWindow` doesn't receive key events when borderless.

- **HotkeyManager** (`Services/HotkeyManager.swift`) - Carbon API wrapper for system-wide keyboard shortcuts. Uses `RegisterEventHotKey` because there's no native Swift API for global hotkeys.

- **FileService** (`Services/FileService.swift`) - Singleton handling text file I/O with 500ms debounced auto-save. Uses Combine's `@Published` for reactive UI updates.

- **AppSettings** (`Models/AppSettings.swift`) - Singleton using `@AppStorage` for UserDefaults-backed preferences. Contains theme definitions (`AppTheme` enum) and shortcut key configuration.

- **HashtagState** (`Views/EditorTextView.swift`) - Singleton tracking used hashtags across the document. Maintains counts, recent usage order, and provides matching suggestions for autocomplete.

- **KeyboardShortcutsManager** (`Services/KeyboardShortcutsManager.swift`) - Manages in-app keyboard shortcuts using the KeyboardShortcuts library. Handles search, navigation, formatting, and tag jump shortcuts.

### Communication Patterns

Cross-component communication uses `NotificationCenter`:
- `.focusQuickEntry` - Focus the quick entry text field when panel opens
- `.hotkeyChanged` - Re-register global hotkey when user changes shortcut
- `.tagJump` - Jump to next occurrence of hashtag at cursor
- `.hashtagClicked` - Highlight all occurrences of clicked hashtag
- `.clearHashtagFilter` - Clear hashtag highlight filter

### Window Behavior

The app uses `NSApp.setActivationPolicy(.accessory)` combined with `LSUIElement = true` in Info.plist to hide from dock. The panel uses `.nonactivatingPanel` collection behavior to appear over other apps without stealing focus aggressively.

## Project Structure

```
/
├── appcast.xml              # Sparkle update feed (MUST be at repo root)
├── CLAUDE.md
└── endless.txt/
    ├── project.yml          # XcodeGen configuration
    ├── dist/                # Build output (gitignored)
    └── NvrEndingTxt/
        ├── Info.plist       # LSUIElement = true
        ├── Services/        # FileService, HotkeyManager, LaunchAtLoginManager
        ├── Models/          # AppSettings, themes
        └── Views/           # ContentView, QuickEntryView, SettingsView, FloatingPanel
```

## Distribution

When packaging the app for release:
- The app must be named **endless.txt** (not NvrEndingTxt)
- The distributed `.app` bundle should be `endless.txt.app`
- The DMG for distribution should be `endless.txt.dmg`

### Developer ID Signing

The app is signed with **Developer ID Application: Jun Hao Lim (454K5WYH9Y)**.

**Automated Build:** Use the provided build script for a complete Developer ID signed release:

```bash
cd endless.txt
./build-release.sh
```

The script handles:
1. Clean builds
2. XcodeGen project regeneration
3. Release build with Developer ID signing
4. Code signature verification
5. Optional notarization (recommended)
6. DMG creation
7. Sparkle signature generation

### Manual Build (Advanced)

If you need to build manually:

```bash
cd endless.txt

# Clean and regenerate
rm -rf ~/Library/Developer/Xcode/DerivedData/NvrEndingTxt-*
rm -rf dist build
xcodegen generate

# Build with Developer ID
xcodebuild \
    -project NvrEndingTxt.xcodeproj \
    -scheme NvrEndingTxt \
    -configuration Release \
    -derivedDataPath ./build \
    CODE_SIGN_IDENTITY="Developer ID Application: Jun Hao Lim (454K5WYH9Y)" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

# Copy and verify
mkdir -p dist
cp -R ./build/Build/Products/Release/NvrEndingTxt.app dist/
codesign --verify --deep --strict --verbose=2 dist/NvrEndingTxt.app

# Notarize (optional but recommended)
cd dist
ditto -c -k --keepParent NvrEndingTxt.app NvrEndingTxt.zip
xcrun notarytool submit NvrEndingTxt.zip --apple-id YOUR_APPLE_ID --team-id 454K5WYH9Y --wait
xcrun stapler staple NvrEndingTxt.app
rm NvrEndingTxt.zip

# Rename and create DMG
cp -R NvrEndingTxt.app "endless.txt.app"
mkdir -p dmg_contents
cp -R "endless.txt.app" dmg_contents/
ln -sf /Applications dmg_contents/Applications
hdiutil create -volname "endless.txt" -srcfolder dmg_contents -ov -format UDZO endless.txt.dmg
rm -rf dmg_contents
```

### Code Signing Notes

**Developer ID Requirements:**
- Hardened Runtime is enabled (`ENABLE_HARDENED_RUNTIME: YES`)
- Entitlements disable App Sandbox (required for global hotkeys via Carbon API)
- Additional entitlements allow loading Sparkle framework signed by different team
- Code signature includes `--timestamp` for long-term validity

**Notarization:**
- Recommended for seamless user experience (no Gatekeeper warnings)
- Requires Apple ID app-specific password (generate at appleid.apple.com)
- Uses `notarytool` (modern replacement for `altool`)
- Ticket is stapled to the app bundle before DMG creation

### Complete Release Workflow

When releasing a new version, follow these steps in order:

**1. Update version numbers in `endless.txt/project.yml`:**
```yaml
MARKETING_VERSION: "1.x.x"      # User-visible version
CURRENT_PROJECT_VERSION: "N"     # Build number (increment each release)
```

**2. Regenerate Xcode project and fix Info.plist:**
```bash
cd endless.txt
xcodegen generate

# xcodegen overwrites Info.plist with hardcoded versions - fix it:
# Change CFBundleShortVersionString from "1.0" to "$(MARKETING_VERSION)"
# Change CFBundleVersion from "1" to "$(CURRENT_PROJECT_VERSION)"
```

**3. Build, sign, and create DMG** (see Build and Package section above)

**4. Sign DMG for Sparkle auto-updates:**
```bash
# Find sign_update tool (after building, it's in DerivedData)
SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -path "*/Sparkle/bin/*" 2>/dev/null | head -1)
$SIGN_TOOL endless.txt.dmg
# Copy the output signature for appcast.xml
```

**5. Update appcast.xml (IMPORTANT: at REPO ROOT, not in endless.txt/):**
```bash
# Edit /appcast.xml (NOT endless.txt/appcast.xml)
# Add new <item> at the TOP with:
# - sparkle:version = build number
# - sparkle:shortVersionString = marketing version
# - sparkle:edSignature = signature from step 4
# - length = file size in bytes
```

**6. Commit and push:**
```bash
git add endless.txt/ appcast.xml
git commit -m "Release v1.x.x"
git push origin main
```

**7. Create GitHub release:**
```bash
gh release create v1.x.x --title "endless.txt v1.x.x" --notes "Release notes" endless.txt/dist/endless.txt.dmg
```

### Important Notes

- **appcast.xml location:** Must be at REPO ROOT (`/appcast.xml`), not in `endless.txt/`. The SUFeedURL points to `https://raw.githubusercontent.com/.../main/appcast.xml`
- **Info.plist versions:** xcodegen overwrites with hardcoded "1.0" - always check and fix after running `xcodegen generate`
- The internal Xcode project uses `NvrEndingTxt` as the target name, but the user-facing app name is `endless.txt` (set via `CFBundleDisplayName` in Info.plist)

## Git Commits

Do not include "Co-Authored-By: Claude" or any Claude co-author mentions in commit messages.

## GitHub Account

Before pushing, creating releases, or any `gh` commands for this repo, verify the active `gh` account is `oahnuj` (which has access to the `starigade` org). Run `gh auth status` to check, and `gh auth switch --user oahnuj` if needed. Switch back to the previous account after the operation.

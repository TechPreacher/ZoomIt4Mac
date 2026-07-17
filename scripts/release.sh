#!/usr/bin/env bash
set -euo pipefail

# One-time setup:
#   1. Developer ID Application certificate installed in the login keychain
#   2. xcrun notarytool store-credentials zoomit-notary \
#        --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>
#   3. Sparkle EdDSA key in the login keychain (one-time: run generate_keys
#      from the Sparkle SPM artifacts; public key lives in project.yml).
#
# Per release:
#   - Bump MARKETING_VERSION *and* CURRENT_PROJECT_VERSION in project.yml
#     (Sparkle compares CFBundleVersion — it must increase every release).
#   - Publish the GitHub release with build/ZoomIt4Mac-<version>.zip attached
#     BEFORE pushing the appcast.xml commit to main (the feed must never
#     point at a missing asset).
#   - Homebrew cask: zoomit4mac cask in TechPreacher/homebrew-tap should
#     declare `auto_updates true` (the app self-updates via Sparkle).

SCHEME=ZoomIt4Mac
ARCHIVE=build/ZoomIt4Mac.xcarchive
EXPORT=build/export
PROFILE="${NOTARY_PROFILE:-zoomit-notary}"

mkdir -p build
xcodegen

xcodebuild -project ZoomIt4Mac.xcodeproj -scheme "$SCHEME" -configuration Release \
  archive -archivePath "$ARCHIVE"

cat > build/exportOptions.plist <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath "$EXPORT" \
  -exportOptionsPlist build/exportOptions.plist

ditto -c -k --keepParent "$EXPORT/ZoomIt4Mac.app" build/ZoomIt4Mac.zip
xcrun notarytool submit build/ZoomIt4Mac.zip --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$EXPORT/ZoomIt4Mac.app"
ditto -c -k --keepParent "$EXPORT/ZoomIt4Mac.app" build/ZoomIt4Mac-notarized.zip

# DMG: stapled app + /Applications symlink; the DMG is signed, notarized,
# and stapled itself so Gatekeeper accepts it before it is ever mounted.
STAGING=build/dmg
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$EXPORT/ZoomIt4Mac.app" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "ZoomIt4Mac" -srcfolder "$STAGING" -ov -format UDZO build/ZoomIt4Mac.dmg
codesign --force --sign "Developer ID Application" build/ZoomIt4Mac.dmg
xcrun notarytool submit build/ZoomIt4Mac.dmg --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/ZoomIt4Mac.dmg

# Sparkle appcast: sign this build and regenerate the feed (single latest
# entry — Sparkle only needs the newest version). Signing uses the EdDSA
# private key from the login keychain.
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | tr -d '"' | head -1)
SPARKLE_BIN=$(dirname "$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*SourcePackages/artifacts/*' -name generate_appcast 2>/dev/null | head -1)")
APPCAST_DIR=build/appcast
rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp build/ZoomIt4Mac-notarized.zip "$APPCAST_DIR/ZoomIt4Mac-$VERSION.zip"
"$SPARKLE_BIN/generate_appcast" "$APPCAST_DIR" \
  --download-url-prefix "https://github.com/TechPreacher/ZoomIt4Mac/releases/download/v$VERSION/"
cp "$APPCAST_DIR/appcast.xml" appcast.xml

echo "Done: build/ZoomIt4Mac-notarized.zip, build/ZoomIt4Mac.dmg, build/appcast/ZoomIt4Mac-$VERSION.zip"
echo "Next: publish the GitHub release with ZoomIt4Mac-$VERSION.zip attached, THEN commit + push appcast.xml to main."

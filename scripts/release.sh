#!/usr/bin/env bash
set -euo pipefail

# One-time setup:
#   1. Developer ID Application certificate installed in the login keychain
#   2. xcrun notarytool store-credentials zoomit-notary \
#        --apple-id <apple-id> --team-id <team-id> --password <app-specific-password>

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

echo "Done: build/ZoomIt4Mac-notarized.zip and build/ZoomIt4Mac.dmg"

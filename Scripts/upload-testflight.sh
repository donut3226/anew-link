#!/bin/zsh
# Archives a Release build and uploads it to App Store Connect (TestFlight).
# The build number is the number of git commits, so every upload gets a higher one.
# Signing uses the paid team in Xcode (Settings > Accounts must have the Gmail Apple ID).
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=$(git rev-list --count HEAD)
OUT=$(mktemp -d)
echo "Archiving build $BUILD..."
xcodebuild -project WenaCompanion.xcodeproj -scheme MyApp -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$OUT/AnewLink.xcarchive" \
  -allowProvisioningUpdates CURRENT_PROJECT_VERSION="$BUILD" archive -quiet

echo "Uploading build $BUILD..."
xcodebuild -exportArchive -archivePath "$OUT/AnewLink.xcarchive" \
  -exportOptionsPlist Config/ExportOptions.plist -exportPath "$OUT/export" \
  -allowProvisioningUpdates 2>&1 | grep -E "Upload|error|EXPORT" || true
echo "Done. Build $BUILD appears in App Store Connect > TestFlight after processing."

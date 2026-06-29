#!/bin/sh
# Xcode Cloud pre-xcodebuild — unique CFBundleVersion every archive (TestFlight dedupes on this).
set -e
set -o pipefail

cd "$CI_PRIMARY_REPOSITORY_PATH"

INFO_PLIST="MorningVault/Info.plist"
PBXPROJ="MorningVault.xcodeproj/project.pbxproj"

if [ ! -f "$INFO_PLIST" ]; then
  echo ":: ERROR: missing $INFO_PLIST ::"
  exit 1
fi

if [ ! -f "$PBXPROJ" ]; then
  echo ":: ERROR: missing $PBXPROJ — ci_post_clone.sh must run xcodegen or commit the project ::"
  exit 1
fi

LOCAL=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" | tr -d '\n')
echo ":: Local CFBundleVersion in Info.plist: $LOCAL ::"

if [ -n "$CI_BUILD_NUMBER" ]; then
  NEW_NUMBER="$CI_BUILD_NUMBER"
  # Xcode Cloud counter can lag behind committed plist; never regress.
  if [ "$NEW_NUMBER" -lt "$LOCAL" ] 2>/dev/null; then
    NEW_NUMBER=$((LOCAL + 1))
  fi
  echo ":: Using CI_BUILD_NUMBER (adjusted if needed) as CFBundleVersion: $NEW_NUMBER ::"
else
  NEW_NUMBER=$((LOCAL + 1))
  echo ":: Fallback bump CFBundleVersion: $LOCAL -> $NEW_NUMBER ::"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_NUMBER" "$INFO_PLIST"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_NUMBER;/g" "$PBXPROJ"

echo ":: CFBundleVersion is now $NEW_NUMBER ::"
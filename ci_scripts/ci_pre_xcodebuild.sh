#!/bin/sh
# Xcode Cloud pre-xcodebuild hook — unique CFBundleVersion every archive.
# TestFlight rejects duplicate CFBundleVersion; reading committed Info.plist + 1
# always produced "2" and blocked every push after the first successful upload.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

INFO_PLIST="MorningVault/Info.plist"
PBXPROJ="MorningVault.xcodeproj/project.pbxproj"

# Xcode Cloud exposes a monotonic CI_BUILD_NUMBER (13, 14, …) — use it when present.
if [ -n "$CI_BUILD_NUMBER" ]; then
  NEW_NUMBER="$CI_BUILD_NUMBER"
  echo ":: Using CI_BUILD_NUMBER as CFBundleVersion: $NEW_NUMBER ::"
else
  OLD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST" | tr -d '\n')
  NEW_NUMBER=$((OLD_NUMBER + 1))
  echo ":: Local/fallback bump CFBundleVersion: $OLD_NUMBER -> $NEW_NUMBER ::"
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion \"$NEW_NUMBER\"" "$INFO_PLIST"
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_NUMBER;/g" "$PBXPROJ"

echo ":: CFBundleVersion is now $NEW_NUMBER ::"
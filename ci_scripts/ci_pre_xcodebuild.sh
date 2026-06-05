#!/bin/sh
# Xcode Cloud pre-xcodebuild hook
# Runs after the project is generated and BEFORE xcodebuild archive is invoked.
# Bumps CFBundleVersion (a.k.a. CURRENT_PROJECT_VERSION) so each TestFlight build
# is treated as a new version, not a duplicate.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Use agvtool to bump the build number. Works with XcodeGen-generated projects
# because the version is stored in the project's xcconfig-like build settings.
NEW_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" MorningVault/Info.plist)
NEW_NUMBER=$((NEW_NUMBER + 1))
echo ":: Bumping CFBundleVersion: $((NEW_NUMBER - 1)) -> $NEW_NUMBER ::"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_NUMBER" MorningVault/Info.plist

# Also update the pbxproj's CURRENT_PROJECT_VERSION setting so it stays in sync
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_NUMBER;/g" MorningVault.xcodeproj/project.pbxproj

echo ":: CFBundleVersion is now $NEW_NUMBER ::"

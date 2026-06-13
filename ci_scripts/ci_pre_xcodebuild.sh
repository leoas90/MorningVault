#!/bin/sh
# Xcode Cloud pre-xcodebuild hook
# Runs after the project is generated and BEFORE xcodebuild archive is invoked.
# Bumps CFBundleVersion (a.k.a. CURRENT_PROJECT_VERSION) so each TestFlight build
# is treated as a new version, not a duplicate.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Read current CFBundleVersion from the manual Info.plist (source of truth)
# Trim any trailing newline from PlistBuddy output for safe arithmetic
OLD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" MorningVault/Info.plist | tr -d '\n')
NEW_NUMBER=$((OLD_NUMBER + 1))

echo ":: Bumping CFBundleVersion: $OLD_NUMBER -> $NEW_NUMBER ::"

# Set as string (use quotes in the PlistBuddy command so the value remains <string> not <integer>)
 /usr/libexec/PlistBuddy -c "Set :CFBundleVersion \"$NEW_NUMBER\"" MorningVault/Info.plist

# Also update the pbxproj's CURRENT_PROJECT_VERSION setting so it stays in sync with the generated project
sed -i '' "s/CURRENT_PROJECT_VERSION = [0-9]*;/CURRENT_PROJECT_VERSION = $NEW_NUMBER;/g" MorningVault.xcodeproj/project.pbxproj

echo ":: CFBundleVersion is now $NEW_NUMBER ::"
#!/bin/sh
# Xcode Cloud post-clone hook
# Runs after Xcode Cloud clones the repo and BEFORE it looks for the .xcodeproj.
# Required because the .xcodeproj is gitignored (XcodeGen regenerates it from project.yml).
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo ":: Installing xcodegen via Homebrew ::"
  brew install xcodegen
fi

echo ":: Running xcodegen generate ::"
xcodegen generate

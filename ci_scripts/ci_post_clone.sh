#!/bin/sh
# Xcode Cloud post-clone hook — ensure MorningVault.xcodeproj exists before archive.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

PBXPROJ="MorningVault.xcodeproj/project.pbxproj"

run_xcodegen() {
  echo ":: Running xcodegen generate ::"
  xcodegen generate
}

if command -v xcodegen >/dev/null 2>&1; then
  run_xcodegen
  exit 0
fi

if [ -f "$PBXPROJ" ]; then
  echo ":: xcodegen not on PATH; using committed $PBXPROJ (skip brew) ::"
  exit 0
fi

echo ":: Installing xcodegen via Homebrew (no auto-update) ::"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_INSTALL_CLEANUP=1
brew install xcodegen
run_xcodegen
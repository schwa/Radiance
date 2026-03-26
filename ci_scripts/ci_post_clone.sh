#!/bin/sh
set -e

if [ "$CI_XCODE_CLOUD" = "TRUE" ]; then
    defaults write com.apple.dt.Xcode IDESkipPackagePluginFingerprintValidatation -bool YES
fi

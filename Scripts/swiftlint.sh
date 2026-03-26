#!/bin/sh

if [ -x "/opt/homebrew/bin/swiftlint" ]; then
  echo "Running SwiftLint..."
  /opt/homebrew/bin/swiftlint --quiet --lenient
elif which swiftlint >/dev/null 2>&1; then
  echo "Running SwiftLint from PATH..."
  swiftlint --quiet --lenient
else
  echo "warning: SwiftLint not installed. Get it from https://github.com/realm/SwiftLint"
fi

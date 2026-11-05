#!/bin/zsh
# Run the unit test suite (Swift Testing). Usage: ./scripts/test.sh
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild test -project Nimotch.xcodeproj -scheme Nimotch -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' 2>&1 \
  | grep -E "✔|✘|error:|Test run|passed|failed|TEST (SUCCEEDED|FAILED)" || true
test ${pipestatus[1]} -eq 0

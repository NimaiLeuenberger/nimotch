#!/bin/zsh
# Build nimotch (Debug) and (re)launch it.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Nimotch.xcodeproj -scheme Nimotch -configuration Debug \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' -quiet build
pkill -x nimotch 2>/dev/null || true
open build/Build/Products/Debug/nimotch.app

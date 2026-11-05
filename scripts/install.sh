#!/bin/zsh
# Build a Release copy, install it to /Applications and start it.
# The installed app registers itself as a login item on its first launch.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate --quiet
xcodebuild -project Nimotch.xcodeproj -scheme Nimotch -configuration Release \
  -derivedDataPath build -destination 'platform=macOS,arch=arm64' -quiet build
pkill -x nimotch 2>/dev/null || true
sleep 0.5
rm -rf /Applications/nimotch.app
cp -R build/Build/Products/Release/nimotch.app /Applications/
open /Applications/nimotch.app
echo "Installed /Applications/nimotch.app"

#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
app="${CLEANUP_APP_OUTPUT:-$PWD/dist/Yeoback.app}"
if [[ "$app" != /* || "$app" != *.app ]]; then
  print -u2 'CLEANUP_APP_OUTPUT must be an absolute .app path.'
  exit 2
fi
swift build -c release
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
swift scripts/make-icon.swift .build/Cleanup.iconset
iconutil -c icns .build/Cleanup.iconset -o "$app/Contents/Resources/Cleanup.icns"
cp .build/release/Cleanup "$app/Contents/MacOS/Cleanup.new"
mv "$app/Contents/MacOS/Cleanup.new" "$app/Contents/MacOS/Cleanup"
cp Resources/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"
print "Built: $app"

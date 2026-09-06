#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

case "${1:-}" in
  --help) print 'Usage: zsh scripts/package-app.sh [--skip-build]'; exit 0 ;;
  ''|--skip-build) ;;
  *) print -u2 'Usage: zsh scripts/package-app.sh [--skip-build]'; exit 2 ;;
esac
if (( $# > 1 )); then
  print -u2 'Expected at most one option.'
  exit 2
fi
if [[ "${1:-}" != "--skip-build" ]]; then
  zsh scripts/build-app.sh
fi

app="${CLEANUP_APP_OUTPUT:-$PWD/dist/Yeoback.app}"
codesign --verify --strict "$app"
plutil -lint "$app/Contents/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(lipo -archs "$app/Contents/MacOS/Cleanup")
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' || ! "$architecture" =~ '^(arm64|x86_64)$' ]]; then
  print -u2 'Expected a semantic version and a single supported architecture.'
  exit 1
fi

output="$PWD/dist/Yeoback-${version}-${architecture}-local.dmg"
mkdir -p "$PWD/dist"
if [[ -e "$output" ]]; then
  print -u2 "Image already exists; preserve or rename it before rebuilding: $output"
  exit 1
fi

stage=$(mktemp -d "$PWD/.build/package.XXXXXX")
ditto "$app" "$stage/Yeoback.app"
ln -s /Applications "$stage/Applications"
cat > "$stage/Read Me.txt" <<'EOF'
Yeoback for macOS — local preview

Drag Yeoback.app to Applications, then open Yeoback from Applications.
Requires macOS 14 or later on the architecture named in the disk-image filename.
Only the current development Mac has been runtime-verified.

This is an ad-hoc signed local build, not an Apple-notarized public release.
The disk image is intended for local installation and testing.

Choose a folder, filter the results, select items, and review exact paths before
cleaning. Documents and app bundles move to Trash. Supported cache tools remove
their own disposable cache data. App support files are not uninstalled.

Trash moves usually do not free capacity until Trash is emptied in Finder.
Reserve monitoring is advisory, runs only while Yeoback is open, and never
automatically deletes personal files. Settings and recent activity stay locally
in ~/Library/Application Support/Cleanup/state.json. No telemetry is implemented.

Growth saves up to 12 manual folder measurements for up to 3 local folders in
growth.json beside state.json. It does not identify which app caused growth.
EOF
hdiutil create -volname "Yeoback ${version}" -srcfolder "$stage" -format UDZO "$output"
hdiutil verify "$output"
shasum -a 256 "$output" > "$output.sha256"
print "Packaged: $output"
print "Staging retained for inspection: $stage"

#!/bin/zsh
# Build, Developer ID-sign, notarize and staple SwitchUp; output dist/SwitchUp.zip.
# One-time setup: Developer ID cert in the login keychain + `notarytool store-credentials switchup`.
set -e
cd "$(dirname "$0")"

RELEASE=1 BUILD_DIR=build ./build.sh
APP=build/SwitchUp.app
codesign --force --options runtime --timestamp \
  --sign "Developer ID Application: Shailen Parmar (4Y4K23UP57)" "$APP"
codesign --verify --strict "$APP"

mkdir -p dist
rm -f dist/SwitchUp.zip
ditto -c -k --keepParent "$APP" dist/notarize.zip
xcrun notarytool submit dist/notarize.zip --keychain-profile switchup --wait
xcrun stapler staple "$APP"
rm dist/notarize.zip
ditto -c -k --keepParent "$APP" dist/SwitchUp.zip
spctl --assess --type execute --verbose "$APP"
echo "Ready: dist/SwitchUp.zip ($(du -h dist/SwitchUp.zip | cut -f1))"

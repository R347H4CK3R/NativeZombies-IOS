#!/usr/bin/env bash
set -euo pipefail
xcodebuild -project NativeZombies.xcodeproj -scheme NativeZombies \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/Derived ARCHS=arm64 CODE_SIGNING_ALLOWED=NO build
mkdir -p build/unsigned/Payload
cp -R build/Derived/Build/Products/Release-iphoneos/NativeZombies.app build/unsigned/Payload/
/usr/bin/lipo -info build/unsigned/Payload/NativeZombies.app/NativeZombies
(cd build/unsigned && /usr/bin/zip -qry ../Afterlight-unsigned.ipa Payload)

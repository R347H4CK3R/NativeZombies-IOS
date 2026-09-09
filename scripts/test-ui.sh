#!/usr/bin/env bash
set -euo pipefail
RUNTIME=$(xcrun simctl list runtimes -j | python3 -c 'import json,sys; print(next(r["identifier"] for r in json.load(sys.stdin)["runtimes"] if r["isAvailable"] and "iOS" in r["name"]))')
SIMULATOR_ID=$(xcrun simctl create 'Afterlight iPhone 16 Plus' 'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Plus' "$RUNTIME")
trap 'xcrun xcresulttool export attachments --path build/UITests.xcresult --output-path build/screenshots || true' EXIT
xcodebuild -project NativeZombies.xcodeproj -scheme NativeZombies \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" -parallel-testing-enabled NO \
  -resultBundlePath build/UITests.xcresult CODE_SIGNING_ALLOWED=NO test

# NativeZombies-IOS

A native iOS Zombies-style prototype with a clean asset-import pipeline for user-owned PS3 game data.

## Current status

The repository now includes:

- native SwiftUI iOS application shell
- round, points, ammo and reload prototype logic
- data-driven weapon definitions
- imported-asset manifest support
- PS3 install inventory tool
- BO2 / BO3 container classification groundwork
- XcodeGen project generation
- GitHub Actions unsigned IPA packaging

## PS3 asset workflow

This repository does **not** contain Call of Duty maps, models, textures, sounds, animations or other proprietary game data.

For a legally obtained PS3 dump:

```bash
python3 Tools/ps3_inventory.py /path/to/PS3_GAME/USRDIR --hash
```

That produces `asset-manifest.json`, which is the input for the next game-specific conversion stages.

BO2/T6 uses Treyarch FastFile/zone containers. BO3 uses a later container/layout and is handled separately.

## Build

Local/macOS:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project NativeZombies.xcodeproj -scheme NativeZombies -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build
```

GitHub Actions also packages an unsigned `.ipa` artifact suitable for later signing with your normal iOS sideloading workflow.

## Asset policy

Keep user-owned extracted assets in `UserAssets/` or `ImportedAssets/`. Both are ignored by git and should not be committed to the public repository.

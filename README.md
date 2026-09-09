# Afterlight: Outpost — NativeZombies iOS

An offline, first-person round-survival prototype for ARM64 iPhone and iPad. Built with Swift, UIKit, Metal, and GameController. Version 0.2 adds selected textures and sound effects converted from the supplied PS3 Zombies files. The native simulation runs without an emulator, JIT, or PS3 executable.

## Playable scope

- Three connected areas in a small procedural low-poly outpost; buy doors to unlock routes.
- Escalating rounds, up to 24 concurrent zombies, increasing enemy health and speed, and an eight-second break between rounds.
- Points for hits, headshots, eliminations, and limited barricade repairs.
- Five original weapons: service pistol, SMG, shotgun, assault rifle, and energy lance; two inventory slots, magazines, reserves, reloads, ADS, spread, and hitscan occlusion.
- Wall weapon purchases and ammo refills; a 950-point random supply cache with a three-second roll and twelve-second claim window.
- Iron Heart (health), Quick Hands (reload speed), and Fleet Foot (movement speed) perks.
- Barricades that enemies break and the player can repair. Repair rewards are capped per barricade per round.
- Grid pathfinding through open doors, wall collision, melee cooldowns, regeneration, death, restart, and a saved best round.
- Landscape multitouch controls, compatible extended game controllers, imported ambient/interaction sounds plus synthesized weapon effects, hit markers, HUD, pause menu, and automatic pause on background/controller disconnect.

This is a gameplay prototype, not a recreation of BO2's maps, graphics, campaign, networking, or complete Zombies feature set. The Outpost layout, collision, characters, and weapon geometry are generated in code. The original Town map has NOT been imported: its fastfile geometry remains unverified. Four texture images and five MP3 effects are bundled, with source keys, conversion details, and SHA-256 hashes in `Resources/Imported/manifest.json`. There is no co-op, persistent run save, advanced animation, or device performance certification yet. iOS 17 is the minimum deployment target; iPhone 16 Plus and iOS 27 beta require physical-device testing.

## Build an IPA without a local Mac

1. Open this repository's **Actions → Build iOS IPA**. Pushes to `main` also run the workflow.
2. Wait for simulation tests, imported-asset decoding checks, the ARM64 build, and the iPhone 16 Plus simulator smoke test to pass.
3. Download the **Afterlight-unsigned-N** artifact and unzip it to get `Afterlight-unsigned.ipa`.
4. Sign the IPA using your chosen iOS signing workflow before installing it. An unsigned IPA cannot be installed directly.

GitHub's macOS runner uses Xcode command-line tools remotely; you do not need Xcode on your Windows PC. GitHub runner availability and account quotas still apply.

### Optional ad hoc signed IPA

Create an Apple Distribution certificate exported as a password-protected `.p12`, register the phone's UDID, and create an **ad hoc distribution profile** for `com.r347h4ck3r.nativezombies` that includes that device. Add these as GitHub repository **Actions secrets**, never as committed files or chat messages:

| Secret | Value |
| --- | --- |
| `CERTIFICATE_P12_BASE64` | Base64 of the P12, without line breaks |
| `CERTIFICATE_PASSWORD` | P12 export password |
| `PROVISIONING_PROFILE_BASE64` | Base64 of the ad hoc `.mobileprovision`, without line breaks |

Run **Build iOS IPA → Run workflow**, enabling **signed**. The workflow validates profile identity, expiry, and distribution type, imports signing material into a temporary keychain, and exports an ad hoc IPA. The profile must include your device; the workflow cannot register a device or create Apple credentials for you. The signed route is unverified until real credentials are supplied. Unsigned builds never read signing secrets.

## Controls

| Action | Touch | Controller |
| --- | --- | --- |
| Move / look | Left stick / drag right | Left / right sticks |
| Fire / aim | Hold FIRE / AIM; drag FIRE to track | RT / LT |
| Interact / repair | USE (hold to repeat) | A |
| Reload / weapon swap | RELOAD / SWAP | X / Y |
| Sprint | Hold RUN | Hold LB |
| Crouch / jump | CROUCH / JUMP | B / RB |
| Pause / resume | II / RESUME | Menu |

Look sensitivity and sound can be changed in the pause menu. Teal stations sell weapons, gold marks doors and the supply cache, and colored vending machines grant perks. Face a station within roughly two metres to see its prompt. Start with 500 points; the starting SMG costs 500. Each purchased door changes both collision and enemy routing.

## Structure and validation

- `Sources/Core/Game.swift`: platform-independent simulation.
- `Sources/Platform`: app lifecycle, input/HUD, textured Metal geometry/shaders, and imported/synthesized audio.
- `Tests`: gameplay regression tests run with `swift test`.
- `project.yml`: XcodeGen project definition.
- `scripts`: unsigned device packaging and optional ad hoc export.
- `.github/workflows/ios.yml`: macOS CI and downloadable IPA artifacts.

On a Mac: install XcodeGen, run `swift test`, `xcodegen generate`, then `bash scripts/build-unsigned.sh`. Device testing should check multitouch aim/fire/movement, Bluetooth controller disconnect/reconnect, background pause, perk/door purchases, 15+ rounds, sustained temperature/frame rate, and signing/install on the exact iOS beta. Compilation alone does not establish those results.

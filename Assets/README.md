# User-owned game assets

This repository does not include Call of Duty game data.

The intended workflow is:

1. Start with a legally obtained PS3 installation/dump.
2. Point `Tools/ps3_inventory.py` at the extracted `PS3_GAME/USRDIR` directory.
3. Review the generated manifest.
4. Add game-specific conversion stages for supported containers.
5. Copy converted, user-owned runtime assets into `ImportedAssets/` locally.

Do not commit proprietary game assets to this public repository.

## Current scope

- BO2 / T6 PS3 container identification
- BO3 PS3 container identification
- recursive inventory
- SHA-256 hashing on request
- JSON manifest generation

Actual model, texture, animation, audio and map conversion will be implemented per asset type after representative user-owned files are inspected.

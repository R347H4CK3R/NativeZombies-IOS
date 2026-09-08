#!/usr/bin/env python3
"""Inventory a user-owned PS3 Call of Duty install without redistributing assets."""

from __future__ import annotations

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


KNOWN_EXTENSIONS = {
    ".ff": "fastfile",
    ".pak": "package",
    ".xpak": "xpak",
    ".iwd": "iwd",
    ".sabs": "sound-bank",
    ".sabl": "sound-bank",
    ".bik": "video",
    ".sprx": "ps3-module",
    ".self": "ps3-executable",
    ".bin": "binary",
}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def classify(path: Path) -> str:
    return KNOWN_EXTENSIONS.get(path.suffix.lower(), "other")


def detect_game(root: Path) -> str:
    names = "\n".join(p.name.lower() for p in root.rglob("*") if p.is_file())
    if "t6" in names or "blackops2" in names:
        return "BO2/T6"
    if "bo3" in names or "blackops3" in names:
        return "BO3"
    return "unknown"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path, help="Extracted PS3_GAME/USRDIR directory")
    parser.add_argument("-o", "--output", type=Path, default=Path("asset-manifest.json"))
    parser.add_argument("--hash", action="store_true", help="Calculate SHA-256 for every file")
    args = parser.parse_args()

    root = args.root.expanduser().resolve()
    if not root.is_dir():
        raise SystemExit(f"Not a directory: {root}")

    entries = []
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        stat = path.stat()
        entries.append(
            {
                "relativePath": str(path.relative_to(root)),
                "size": stat.st_size,
                "kind": classify(path),
                "sha256": sha256(path) if args.hash else None,
            }
        )

    manifest = {
        "sourcePlatform": "PS3",
        "sourceGame": detect_game(root),
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "entries": entries,
    }

    args.output.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    counts = {}
    for entry in entries:
        counts[entry["kind"]] = counts.get(entry["kind"], 0) + 1

    print(f"Wrote {args.output} with {len(entries)} files")
    for kind, count in sorted(counts.items()):
        print(f"{kind:16} {count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

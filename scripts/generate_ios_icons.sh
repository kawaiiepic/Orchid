#!/usr/bin/env bash
set -euo pipefail

# Decode the committed orchid-glass artwork into Xcode's icon catalog on macOS.
# Apple requires opaque PNG icons (no alpha channel).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/assets/branding/orchid_glass_icon.webp.base64"
CATALOG="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! command -v dwebp >/dev/null 2>&1; then
  brew install webp
fi

base64 -D -i "$SOURCE" -o "$TMP/icon.webp"
dwebp "$TMP/icon.webp" -o "$TMP/rendered.png"
# Round-trip through JPEG to guarantee an opaque RGB image for App Store upload.
sips -s format jpeg -s formatOptions best "$TMP/rendered.png" --out "$TMP/opaque.jpg" >/dev/null
sips -s format png "$TMP/opaque.jpg" --out "$TMP/master.png" >/dev/null

python3 - "$CATALOG" "$TMP/master.png" <<'PY'
import json
import subprocess
import sys
from pathlib import Path

catalog = Path(sys.argv[1])
master = Path(sys.argv[2])
entries = json.loads((catalog / "Contents.json").read_text())["images"]
for entry in entries:
    filename = entry.get("filename")
    if not filename:
        continue
    point_size = float(entry["size"].split("x")[0])
    pixels = round(point_size * float(entry["scale"].rstrip("x")))
    subprocess.run(
        ["sips", "-z", str(pixels), str(pixels), str(master),
         "--out", str(catalog / filename)],
        check=True, stdout=subprocess.DEVNULL,
    )
print(f"Generated {len(entries)} opaque iOS app icons")
PY

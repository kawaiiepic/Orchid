#!/usr/bin/env bash
set -euo pipefail

# Build Orchid's conventional iOS icon and optional iOS 26 dark/tinted
# variants. Keep the normal App Store icon opaque, but NEVER flatten the
# foreground used for system-provided dark/tinted/clear treatments.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/assets/branding/orchid_icon.png"
FOREGROUND="$ROOT/assets/branding/orchid_icon_foreground.png"
CATALOG="$ROOT/ios/Runner/Assets.xcassets/AppIcon.appiconset"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Pillow is used only by the icon build helper, not by the Flutter app.
python3 -m venv "$TMP/venv"
"$TMP/venv/bin/python" -m pip -q install "Pillow>=10,<13"

"$TMP/venv/bin/python" - "$SOURCE" "$FOREGROUND" "$CATALOG" <<'PY'
import json
import sys
from pathlib import Path
from PIL import Image, ImageOps

source, foreground, catalog = map(Path, sys.argv[1:4])
data = json.loads((catalog / "Contents.json").read_text())
base_entries = [e for e in data["images"] if not e.get("appearances")]

# App Store / default icon: preserve existing design while flattening to RGB.
original = Image.open(source).convert("RGBA")
size = (1024, 1024)
original = original.resize(size, Image.Resampling.LANCZOS)
# Orchid's dark ink matches the app, avoiding the old JPEG white matte.
base = Image.new("RGBA", size, (16, 16, 24, 255))
base.alpha_composite(original)
base = base.convert("RGB")

for entry in base_entries:
    filename = entry.get("filename")
    if not filename:
        continue
    point_size = float(entry["size"].split("x")[0])
    scale = float(entry["scale"].rstrip("x"))
    pixels = round(point_size * scale)
    icon = base.resize((pixels, pixels), Image.Resampling.LANCZOS)
    icon.save(catalog / filename, format="PNG")

# A foreground image is required to *accurately* remove the baked-in
# background. Never try to erase pixels based on an assumed background color.
variants = []
# If the existing branding PNG already has real transparency, it can act as
# the foreground directly. Otherwise a separate cutout must be provided.
foreground_source = foreground if foreground.exists() else source
candidate = Image.open(foreground_source).convert("RGBA")
has_transparency = candidate.getchannel("A").getextrema()[0] < 255
if foreground.exists() or has_transparency:
    layer = candidate
    layer = layer.resize(size, Image.Resampling.LANCZOS)
    alpha = layer.getchannel("A")
    if alpha.getextrema()[0] == 255:
        raise SystemExit(
            "Orchid iOS foreground artwork is fully opaque. "
            "Export orchid_icon_foreground.png with a transparent background."
        )

    dark_file = "Icon-App-Dark-1024.png"
    tinted_file = "Icon-App-Tinted-1024.png"
    layer.save(catalog / dark_file, format="PNG")

    # iOS expects the tinted variant's glyph to be grayscale with alpha.
    grayscale = ImageOps.grayscale(layer)
    mono = Image.merge("RGBA", (grayscale, grayscale, grayscale, alpha))
    mono.save(catalog / tinted_file, format="PNG")
    for mode, filename in (("dark", dark_file), ("tinted", tinted_file)):
        variants.append({
            "appearances": [{"appearance": "luminosity", "value": mode}],
            "filename": filename,
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024",
        })
else:
    print(
        "No orchid_icon_foreground.png: iOS will automatically generate "
        "dark, tinted and clear appearances from the default icon. "
        "Add transparent foreground artwork for dedicated variants."
    )

data["images"] = base_entries + variants
(catalog / "Contents.json").write_text(json.dumps(data, indent=2) + "\n")
print(f"Generated {len(base_entries)} opaque icons and {len(variants)} appearance variants")
PY

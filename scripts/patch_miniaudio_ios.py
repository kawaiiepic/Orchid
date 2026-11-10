#!/usr/bin/env python3
"""Apply Orchid's focused miniaudio_player 3.0.2 iOS compilation hotfix.

Dart's Native Assets hook invokes the package's Cargo build.rs directly.
Compiling the iOS bridge as C breaks Foundation/Objective-C headers. Until the
upstream package fixes build.rs, patch only the resolved dependency's build
script after `flutter pub get`. This is idempotent and fails closed on changes.
"""
import json
from pathlib import Path
from urllib.parse import unquote, urlparse

project = Path(__file__).resolve().parent.parent
config_path = project / ".dart_tool" / "package_config.json"
if not config_path.exists():
    raise SystemExit("Missing .dart_tool/package_config.json. Run flutter pub get first.")

config = json.loads(config_path.read_text())
package = next((p for p in config["packages"] if p["name"] == "miniaudio_player"), None)
if package is None:
    raise SystemExit("miniaudio_player is absent from package_config.json.")

root_uri = package["rootUri"]
if root_uri.startswith("file:"):
    parsed = urlparse(root_uri)
    root = Path(unquote(parsed.path))
else:
    root = (config_path.parent / unquote(root_uri)).resolve()
manifest = root / "pubspec.yaml"
script = root / "rust" / "build.rs"
if not script.is_file() or not manifest.is_file():
    raise SystemExit(f"Cannot find miniaudio native build.rs in {root}")
if not any(line.strip() == "version: 3.0.2" for line in manifest.read_text().splitlines()):
    raise SystemExit("This patch was reviewed for miniaudio_player 3.0.2 only.")

source = script.read_text()
marker = '    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();'
patch = '''    // iOS miniaudio imports Foundation and Objective-C constructs.
    // The cc crate otherwise treats the .c bridge as plain C and fails
    // while parsing Apple's NSObjCRuntime.h and NSString declarations.
    if target_os == "ios" {
        build.flag("-x").flag("objective-c");
        println!("cargo:rustc-link-lib=framework=Foundation");
    }
'''
if 'build.flag("-x").flag("objective-c")' in source:
    print(f"miniaudio_player already patched: {script}")
elif source.count(marker) != 1:
    raise SystemExit(f"Unexpected upstream build.rs layout: {script}")
else:
    source = source.replace(marker, marker + "\n" + patch, 1)
    script.write_text(source)
    print(f"Patched miniaudio_player iOS native build: {script}")

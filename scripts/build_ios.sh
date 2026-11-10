#!/usr/bin/env bash
# Use the published miniaudio_player dependency with Orchid's narrowly scoped
# iOS build.rs hotfix until a package release includes the upstream fix.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
python3 scripts/patch_miniaudio_ios.py
exec flutter build ios "$@"

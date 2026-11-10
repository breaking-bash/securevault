#!/usr/bin/env bash
# =============================================================================
# SecureVault — Linux build script
# =============================================================================
# Prerequisites (Debian/Ubuntu):
#   sudo apt-get install -y clang cmake ninja-build pkg-config \
#        libgtk-3-dev liblzma-dev libsqlite3-dev libstdc++-12-dev
#   + Flutter SDK on PATH, then: flutter config --enable-linux-desktop
#
# Usage:  ./scripts/build_linux.sh          # build release
#         ./scripts/build_linux.sh run      # build + run
# Output: build/linux/x64/release/bundle/securevault
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> flutter pub get"
flutter pub get

echo "==> building Linux release"
flutter build linux --release

BIN="build/linux/x64/release/bundle/securevault"
echo ""
echo "BUILD SUCCEEDED"
echo "Executable: $BIN"
echo "App bundle: build/linux/x64/release/bundle/  (ship the whole folder)"

if [[ "${1:-}" == "run" ]]; then
  echo "==> launching..."
  exec "$BIN"
fi

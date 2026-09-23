#!/usr/bin/env bash
# Build FreeRDP for macOS embedding (client libs). Optional for first slice (Stub works without it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENDOR="$ROOT/native/vendor/FreeRDP"
PREFIX="$ROOT/native/dist/freerdp-macos"
BUILD_DIR="$ROOT/native/build/freerdp-macos"

echo "==> macrdp FreeRDP macOS build"
echo "    vendor: $VENDOR"
echo "    prefix: $PREFIX"

if [[ ! -f "$VENDOR/CMakeLists.txt" ]]; then
  echo "FreeRDP submodule missing. Initializing…"
  git -C "$ROOT" submodule update --init --depth 1 native/vendor/FreeRDP
fi

if [[ ! -f "$VENDOR/CMakeLists.txt" ]]; then
  echo "ERROR: native/vendor/FreeRDP still empty. Clone FreeRDP manually:"
  echo "  git -C \"$ROOT\" submodule update --init native/vendor/FreeRDP"
  exit 1
fi

mkdir -p "$BUILD_DIR" "$PREFIX"
cmake -S "$VENDOR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DWITH_CLIENT=ON \
  -DWITH_CLIENT_SDL=OFF \
  -DWITH_SERVER=OFF \
  -DWITH_SAMPLE=OFF \
  -DWITH_FFMPEG=OFF \
  -DWITH_VAAPI=OFF \
  -DWITH_X11=OFF \
  -DWITH_WAYLAND=OFF \
  -DCHANNEL_URBDRC=OFF \
  -DWITH_MANPAGES=OFF \
  -DBUILD_SHARED_LIBS=ON

cmake --build "$BUILD_DIR" --parallel "$(sysctl -n hw.ncpu)"
cmake --install "$BUILD_DIR"

echo "OK. Re-run: python3 macos/scripts/generate_macos_xcodeproj.py"
echo "Then build MacRDP with RDP_BRIDGE_HAS_FREERDP enabled."

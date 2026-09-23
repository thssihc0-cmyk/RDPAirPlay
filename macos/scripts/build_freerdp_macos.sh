#!/usr/bin/env bash
# Build FreeRDP 3.x client libraries for macOS embedding (MacRDP).
# Stub MacRDP still works without this; with install, regenerating the Xcode
# project enables RDP_BRIDGE_HAS_FREERDP.
set -euo pipefail

export PATH="${HOME}/.local/bin:/usr/local/bin:/opt/homebrew/bin:${PATH}"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENDOR="$ROOT/native/vendor/FreeRDP"
PREFIX="$ROOT/native/dist/freerdp-macos"
BUILD_DIR="$ROOT/native/build/freerdp-macos"
# Prefer Homebrew OpenSSL 1.1 (present on macos8G); allow override.
OPENSSL_ROOT="${FREERDP_MACOS_OPENSSL_PATH:-}"
if [[ -z "$OPENSSL_ROOT" ]]; then
  if [[ -d /usr/local/opt/openssl@1.1 ]]; then
    OPENSSL_ROOT="/usr/local/opt/openssl@1.1"
  elif [[ -d /usr/local/opt/openssl@3 ]]; then
    OPENSSL_ROOT="/usr/local/opt/openssl@3"
  elif [[ -d /opt/homebrew/opt/openssl@3 ]]; then
    OPENSSL_ROOT="/opt/homebrew/opt/openssl@3"
  fi
fi

echo "==> macrdp FreeRDP macOS build"
echo "    vendor:  $VENDOR"
echo "    prefix:  $PREFIX"
echo "    openssl: ${OPENSSL_ROOT:-<system/cmake default>}"

if [[ ! -f "$VENDOR/CMakeLists.txt" ]]; then
  echo "FreeRDP submodule missing. Initializing…"
  git -C "$ROOT" submodule update --init native/vendor/FreeRDP || true
fi

if [[ ! -f "$VENDOR/CMakeLists.txt" ]]; then
  echo "Cloning FreeRDP 3.9.0 (pinned submodule commit unavailable via shallow fetch)…"
  rm -rf "$VENDOR"
  git clone --depth 1 --branch 3.9.0 https://github.com/FreeRDP/FreeRDP.git "$VENDOR"
fi

# Prefer a known-good 3.x for the existing rdp_bridge_freerdp.c API surface.
if [[ -d "$VENDOR/.git" ]] || [[ -f "$VENDOR/.git" ]]; then
  if ! git -C "$VENDOR" describe --tags --exact-match 2>/dev/null | grep -q '^3\.9\.0$'; then
    echo "Checking out FreeRDP 3.9.0…"
    git -C "$VENDOR" fetch --depth 1 origin tag 3.9.0 2>/dev/null || \
      git -C "$VENDOR" fetch --depth 1 origin 3.9.0
    git -C "$VENDOR" checkout -f 3.9.0
  fi
fi

if [[ ! -f "$VENDOR/CMakeLists.txt" ]]; then
  echo "ERROR: FreeRDP sources still missing at $VENDOR"
  exit 1
fi

if ! command -v cmake >/dev/null; then
  echo "ERROR: cmake not found. Install via brew or place cmake on PATH."
  exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$PREFIX"

CMAKE_ARGS=(
  -S "$VENDOR"
  -B "$BUILD_DIR"
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0
  -DBUILD_SHARED_LIBS=ON
  -DWITH_SERVER=OFF
  -DWITH_CLIENT=OFF
  -DWITH_CLIENT_COMMON=ON
  -DWITH_SAMPLE=OFF
  -DWITH_FFMPEG=OFF
  -DWITH_OPENH264=OFF
  -DWITH_SWSCALE=OFF
  -DWITH_OPUS=OFF
  -DWITH_CAIRO=OFF
  -DWITH_WEBP=OFF
  -DWITH_VAAPI=OFF
  -DWITH_X11=OFF
  -DWITH_WAYLAND=OFF
  -DWITH_MACAUDIO=ON
  -DCHANNEL_URBDRC=OFF
  -DWITH_MANPAGES=OFF
  -DWITH_INTERNAL_MD4=ON
  -DWITH_INTERNAL_MD5=ON
  -DWITH_INTERNAL_RC4=ON
)

if [[ -n "$OPENSSL_ROOT" && -d "$OPENSSL_ROOT" ]]; then
  CMAKE_ARGS+=(
    -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT"
    -DOPENSSL_INCLUDE_DIR="$OPENSSL_ROOT/include"
  )
  if [[ -f "$OPENSSL_ROOT/lib/libssl.dylib" ]]; then
    CMAKE_ARGS+=(
      -DOPENSSL_SSL_LIBRARY="$OPENSSL_ROOT/lib/libssl.dylib"
      -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_ROOT/lib/libcrypto.dylib"
    )
  fi
fi

echo "==> Configuring…"
cmake "${CMAKE_ARGS[@]}"

echo "==> Building…"
cmake --build "$BUILD_DIR" --parallel "$(sysctl -n hw.ncpu)"

echo "==> Installing…"
cmake --install "$BUILD_DIR"

echo "==> Installed libs:"
ls -la "$PREFIX/lib" | head -40
echo "OK. Re-run: python3 macos/scripts/generate_macos_xcodeproj.py"
echo "Then: xcodebuild -project macos/MacRDP.xcodeproj -scheme MacRDP -configuration Debug -derivedDataPath macos/build build"

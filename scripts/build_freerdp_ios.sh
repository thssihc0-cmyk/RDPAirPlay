#!/usr/bin/env bash
# 构建 OpenSSL + FreeRDP iOS 静态库
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/native/vendor"
FREERDP_DIR="$VENDOR/FreeRDP"
INSTALL_DIR="$ROOT/native/dist/freerdp"

PLATFORM="${IOS_PLATFORM:-${PLATFORM:-}}"
if [[ -z "$PLATFORM" ]]; then
  case "$(uname -m)" in
    x86_64) PLATFORM="SIMULATOR64" ;;
    *) PLATFORM="SIMULATORARM64" ;;
  esac
fi

if [[ "$PLATFORM" == "OS64" ]]; then
  LIB_SUBDIR="iphoneos"
else
  LIB_SUBDIR="iphonesimulator"
fi
BUILD_DIR="$ROOT/native/build/freerdp-$LIB_SUBDIR"
LIB_OUT="$INSTALL_DIR/lib/$LIB_SUBDIR"
DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-16.0}"
OPENSSL_ROOT="${FREERDP_IOS_OPENSSL_PATH:-$ROOT/native/dist/openssl/iossimulator}"

if [[ "$PLATFORM" == "OS64" ]]; then
  OPENSSL_ROOT="${FREERDP_IOS_OPENSSL_PATH:-$ROOT/native/dist/openssl/ios}"
fi

export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"

echo "==> RDPAirPlay FreeRDP build"
echo "    platform=$PLATFORM  openssl=$OPENSSL_ROOT"

if [[ ! -f "$OPENSSL_ROOT/lib/libssl.a" ]]; then
  echo "==> OpenSSL not found, building..."
  bash "$ROOT/scripts/build_openssl_ios.sh"
fi

if [[ ! -d "$FREERDP_DIR/.git" ]]; then
  echo "==> Cloning FreeRDP..."
  git clone --depth 1 https://github.com/FreeRDP/FreeRDP.git "$FREERDP_DIR"
fi

TOOLCHAIN="$FREERDP_DIR/cmake/ios.toolchain.cmake"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$INSTALL_DIR" "$LIB_OUT"

echo "==> Configuring FreeRDP..."
cmake -S "$FREERDP_DIR" -B "$BUILD_DIR" -G Xcode \
  -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
  -DPLATFORM="$PLATFORM" \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$DEPLOYMENT_TARGET" \
  -DBUILD_SHARED_LIBS=OFF \
  -DWITH_SERVER=OFF \
  -DWITH_CLIENT_COMMON=ON \
  -DWITH_CLIENT=OFF \
  -DWITH_IOSAUDIO=ON \
  -DWITH_MANPAGES=OFF \
  -DWITH_FFMPEG=OFF \
  -DWITH_OPENH264=OFF \
  -DWITH_WEBP=OFF \
  -DWITH_OPUS=OFF \
  -DWITH_CAIRO=OFF \
  -DWITH_SWSCALE=OFF \
  -DWITH_INTERNAL_MD4=ON \
  -DWITH_INTERNAL_MD5=ON \
  -DWITH_INTERNAL_RC4=ON \
  -DOPENSSL_ROOT_DIR="$OPENSSL_ROOT" \
  -DOPENSSL_INCLUDE_DIR="$OPENSSL_ROOT/include" \
  -DOPENSSL_CRYPTO_LIBRARY="$OPENSSL_ROOT/lib/libcrypto.a" \
  -DOPENSSL_SSL_LIBRARY="$OPENSSL_ROOT/lib/libssl.a" \
  -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_DIR"

echo "==> Building (Release)..."
cmake --build "$BUILD_DIR" --config Release \
  --target winpr freerdp freerdp-client \
  2>&1 | tail -20

mkdir -p "$INSTALL_DIR/include" "$LIB_OUT"
rsync -a "$FREERDP_DIR/include/" "$INSTALL_DIR/include/"
rsync -a "$FREERDP_DIR/winpr/include/" "$INSTALL_DIR/include/"
cp "$BUILD_DIR/include/freerdp/config.h" "$INSTALL_DIR/include/freerdp/"
cp "$BUILD_DIR/winpr/include/winpr/config.h" "$INSTALL_DIR/include/winpr/"
cp "$BUILD_DIR/include/freerdp/"*.h "$INSTALL_DIR/include/freerdp/" 2>/dev/null || true

if [[ "$PLATFORM" == "OS64" ]]; then
  SDK_SUFFIX="Release-iphoneos"
else
  SDK_SUFFIX="Release-iphonesimulator"
fi

for lib in libfreerdp-client3.a libfreerdp3.a libwinpr3.a libfreerdp-codecs.a \
           libfreerdp-primitives.a libremdesk-client.a libremdesk-common.a librdpsnd-common.a; do
  find "$BUILD_DIR" -path "*${SDK_SUFFIX}/${lib}" -exec cp {} "$LIB_OUT/" \;
done

if [[ ! -f "$LIB_OUT/libfreerdp3.a" ]]; then
  echo "ERROR: libfreerdp3.a not found under *${SDK_SUFFIX}*" >&2
  exit 1
fi

cat > "$INSTALL_DIR/README.txt" <<EOF
FreeRDP built for $PLATFORM ($LIB_SUBDIR)

Libraries: $LIB_OUT

Link in Xcode (Debug/Release):
  HEADER_SEARCH_PATHS:
    \$(SRCROOT)/../native/dist/freerdp/include
    \$(SRCROOT)/../native/dist/openssl/ios/include          (iphoneos)
    \$(SRCROOT)/../native/dist/openssl/iossimulator/include (iphonesimulator)
  LIBRARY_SEARCH_PATHS:
    \$(SRCROOT)/../native/dist/freerdp/lib/iphoneos          (iphoneos)
    \$(SRCROOT)/../native/dist/freerdp/lib/iphonesimulator   (iphonesimulator)
    \$(SRCROOT)/../native/dist/openssl/ios/lib               (iphoneos)
    \$(SRCROOT)/../native/dist/openssl/iossimulator/lib      (iphonesimulator)
  OTHER_LDFLAGS:
    -ObjC -lfreerdp-client3 -lremdesk-client -lremdesk-common -lrdpsnd-common
    -lfreerdp3 -lfreerdp-codecs -lfreerdp-primitives -lwinpr3 -lssl -lcrypto -lz
    -framework AVFoundation -framework CoreAudio -framework AudioToolbox
  GCC_PREPROCESSOR_DEFINITIONS:
    RDP_BRIDGE_HAS_FREERDP=1

Then rebuild the app. NativeRDPSession will connect to real Windows hosts.
Audio: audin-ios + rdpsnd-ios (FreeRDP built-in).
EOF

echo "==> Done: $LIB_OUT"
ls -la "$LIB_OUT/" 2>/dev/null || true

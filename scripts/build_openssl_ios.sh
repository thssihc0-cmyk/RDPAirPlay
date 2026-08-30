#!/usr/bin/env bash
# 为 iOS 设备 / 模拟器交叉编译 OpenSSL 静态库
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENDOR="$ROOT/native/vendor"
INSTALL_BASE="$ROOT/native/dist/openssl"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.2}"
OPENSSL_TAR="openssl-${OPENSSL_VERSION}.tar.gz"
OPENSSL_URL="https://www.openssl.org/source/${OPENSSL_TAR}"

build_openssl() {
  local sdk="$1"
  local configure_target="$2"
  local out="$3"
  local build_dir="$ROOT/native/build/openssl-${configure_target}"

  echo "==> OpenSSL $configure_target (SDK: $sdk)"
  rm -rf "$out" "$build_dir"
  mkdir -p "$out/lib" "$out/include"

  if [[ ! -f "$VENDOR/$OPENSSL_TAR" ]]; then
    echo "==> Downloading OpenSSL $OPENSSL_VERSION"
    mkdir -p "$VENDOR"
    curl -L "$OPENSSL_URL" -o "$VENDOR/$OPENSSL_TAR"
  fi

  mkdir -p "$build_dir"
  tar -xzf "$VENDOR/$OPENSSL_TAR" -C "$build_dir" --strip-components=1

  export SDKROOT
  SDKROOT="$(xcrun --sdk "$sdk" --show-sdk-path)"
  export PATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH"
  export CC="$(xcrun --sdk "$sdk" -find clang)"
  export CROSS_COMPILE=""
  unset CROSS_TOP CROSS_SDK

  pushd "$build_dir" >/dev/null
  # no-module：provider 编进 libcrypto，避免 iOS 上 dlopen 失败
  # enable-legacy：NLA/NTLM 需要 MD4/RC4
  perl ./Configure "$configure_target" no-shared no-module no-tests no-apps enable-legacy
  make -j"$JOBS" build_libs
  cp libcrypto.a libssl.a "$out/lib/"
  cp -R include/openssl "$out/include/"
  popd >/dev/null

  echo "    -> $out/lib/libssl.a"
}

mkdir -p "$VENDOR"
HOST_ARCH="$(uname -m)"
if [[ "$HOST_ARCH" == "x86_64" ]]; then
  build_openssl iphoneos ios64-xcrun "$INSTALL_BASE/ios"
  build_openssl iphonesimulator iossimulator-x86_64-xcrun "$INSTALL_BASE/iossimulator"
else
  build_openssl iphoneos ios64-xcrun "$INSTALL_BASE/ios"
  build_openssl iphonesimulator iossimulator-arm64-xcrun "$INSTALL_BASE/iossimulator"
fi

cat > "$INSTALL_BASE/README.txt" <<EOF
OpenSSL built for iOS.

ios/          device (arm64)
iossimulator/ simulator ($HOST_ARCH)
EOF

echo "==> OpenSSL ready at $INSTALL_BASE"

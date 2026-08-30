#!/usr/bin/env bash
# 占位：后续接入 FreeRDP iOS 交叉编译
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/native/build"

echo "==> RDPAirPlay native build (stub)"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/README.txt" <<EOF
FreeRDP 尚未集成。
当前 rdp_bridge.c 为 stub，iOS 应用将使用 StubRDPSession。

下一步：
1. 添加 FreeRDP 子模块或预编译 xcframework
2. 在此目录用 CMake 构建 libfreerdp + 依赖
3. 实现 native/src/rdp_bridge_freerdp.c
4. 在 Xcode 中链接并设置 HEADER_SEARCH_PATHS / LIBRARY_SEARCH_PATHS
EOF

echo "==> 完成。输出: $BUILD_DIR/README.txt"

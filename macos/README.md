# macrdp（macOS RDP 客户端）

自用 macOS 原生 RDP 客户端：**SwiftUI 壳 + FreeRDP 内核**，直连 Windows / Windows Server。  
与仓库内 **iOS RDPAirPlay** 产品分离：本目录为独立 macOS target，共享 `native/include` + `rdp_bridge` C API，不改动 iOS UI / AirPlay 流程。

需求基线：项目 Agent Store `docs/requirements.md`（0.3-locked）与弱网方案 A 主路径。

## 已冻结默认（Jack 2026-09-23，不再阻塞）

| ID | 默认 |
|----|------|
| R1 | macOS 13+；Apple Silicon 优先，Intel 尽力 |
| R2 | RDP 8.1+；NLA 默认开；UDP 尽力（不可用不成硬失败） |
| R3 | 弱网验收暂定性 |
| R4 | 剪贴板 text+image；盘符=用户自选文件夹；麦克风=P1（不挡 MVP） |
| R5 | 多屏 P1；打印机 P2 |
| 弱网 | **A** 主路径 + 三色 + 输入优先 + 重连；评估 **UDP (B)** |

代码常量：`MacRDP/Models/ProductDefaults.swift`。

## 首切片能力

| 能力 | 状态 | 需求 ID |
|------|------|---------|
| 主机增删改 + Keychain 密码 | ✅ | F-CONN-01/02/05 |
| 连接状态文案 | ✅ | F-CONN-03 |
| Stub 远程画面 + 键鼠路径 | ✅ | F-DISP-01、F-IN-01 |
| FreeRDP 桥接路径（有库则真连接） | 🔶 | §7.1–7.2 |
| 全彩/灰度/黑白 + 锁定 | ✅ stub | F-DISP-05、F-WN-07 |
| 弱网钩子 A/UDP/重连/输入优先 | ✅ stubs | F-WN-01…05 |
| 剪贴板 / 盘符 / 音频 | ⏳ 后续 | F-CLIP/DRIVE/AUD |

## 构建

```bash
# 在仓库根（或本 worktree）
python3 macos/scripts/generate_macos_xcodeproj.py

# Stub 即可运行（无需 FreeRDP）
xcodebuild -project macos/MacRDP.xcodeproj -scheme MacRDP -configuration Debug \
  -derivedDataPath macos/build build

open macos/build/Build/Products/Debug/MacRDP.app
```

可选：链接 FreeRDP（真远程桌面）

```bash
chmod +x macos/scripts/build_freerdp_macos.sh
./macos/scripts/build_freerdp_macos.sh
python3 macos/scripts/generate_macos_xcodeproj.py
# 再 xcodebuild …
```

## 布局

```
macos/
  MacRDP/                 SwiftUI 应用
  MacRDP.xcodeproj/       由 scripts/generate_macos_xcodeproj.py 生成
  scripts/
    generate_macos_xcodeproj.py
    build_freerdp_macos.sh
  docs/                   macOS 侧开发笔记
```

共享：`../native/include`、`../native/src/rdp_bridge*.c`（未定义 `RDP_BRIDGE_HAS_FREERDP` 时走 stub 实现）。

# macrdp 首切片开发笔记

- 产品：macOS 自用 RDP（非 App Store）
- 与 iOS `app/RDPAirPlay` 解耦；仅共享 `native` C 边界
- 弱网：方案 A 钩子已落；UDP（B）评估桩；无 Windows Agent
- 冻结默认：见 `../README.md` 与 `ProductDefaults.swift`（R1–R5）
- FreeRDP：**3.9.0** via `macos/scripts/build_freerdp_macos.sh` → `native/dist/freerdp-macos`（gitignored）
- 验证：本机 `xcodebuild`；UI 显示 FreeRDP 版本即真内核；无 Windows 主机时无法验证远程画面

## 构建（worktree）

```bash
cd /Users/ssihc0/pro1/macrdp-wt   # 或仓库根
./macos/scripts/build_freerdp_macos.sh
python3 macos/scripts/generate_macos_xcodeproj.py
xcodebuild -project macos/MacRDP.xcodeproj -scheme MacRDP -configuration Debug \
  -derivedDataPath macos/build build
open macos/build/Build/Products/Debug/MacRDP.app
```

原 submodule SHA `c73fb19…` 浅取失败；本地/脚本改用 tag **3.9.0**。

# macrdp 首切片开发笔记

- 产品：macOS 自用 RDP（非 App Store）
- 与 iOS `app/RDPAirPlay` 解耦；仅共享 `native` C 边界
- 弱网：方案 A 钩子已落；UDP（B）评估桩；无 Windows Agent
- 冻结默认：见 `../README.md` 与 `ProductDefaults.swift`（R1–R5）
- 验证：本机 `xcodebuild` + Stub 会话画面/键鼠；真机 Windows 连接待 FreeRDP macOS 库

## 构建（worktree）

```bash
cd /Users/ssihc0/pro1/macrdp-wt   # 或仓库根
python3 macos/scripts/generate_macos_xcodeproj.py
xcodebuild -project macos/MacRDP.xcodeproj -scheme MacRDP -configuration Debug \
  -derivedDataPath macos/build build
open macos/build/Build/Products/Debug/MacRDP.app
```

可选 FreeRDP：`./macos/scripts/build_freerdp_macos.sh`（需先 `git submodule update --init native/vendor/FreeRDP`）。

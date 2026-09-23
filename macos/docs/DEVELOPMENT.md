# macrdp 首切片开发笔记

- 产品：macOS 自用 RDP（非 App Store）
- 与 iOS `app/RDPAirPlay` 解耦；仅共享 `native` C 边界
- 弱网：方案 A 钩子已落；UDP（B）评估桩；无 Windows Agent
- 验证：本机 `xcodebuild` + Stub 会话画面/键鼠；真机 Windows 连接待 FreeRDP macOS 库

# RDP AirPlay 开发指南

配套文档：[REQUIREMENTS.md](REQUIREMENTS.md) · [PROJECT.md](PROJECT.md) · [../README.md](../README.md)

---

## 当前进度（截至 2026-08-30）

| 模块 | 状态 | 需求 ID | 主要文件 |
|------|------|---------|----------|
| 主机列表 / 编辑 / Keychain | ✅ | F-CONN-01/02/03 | `HostListView`, `HostStore`, `KeychainService` |
| 连接状态与错误提示 | ✅ | F-CONN-04/06 | `RDPSessionController`, `RDPErrorFormatter` |
| 分辨率预设与自定义 | ✅ | F-DISP-01 | `HostProfile`, `ResolutionPreset` |
| 会话中改分辨率 | 🔶 | F-DISP-02 | `RDPBridge` 接口已有，Display Control 待完善 |
| 视口缩放 1×–4×、宽高比 | ✅ | F-DISP-03/05 | `RemoteDesktopView` |
| 指针模式光标锚点缩放 | ✅ | F-DISP-03 | `RemoteDesktopView` |
| 放大后才允许拖动画布 | ✅ | F-DISP-03 | `RemoteDesktopView` |
| 色彩模式 全彩/灰度/黑白 | ✅ | F-NET-02/03/04 | `ColorModeProcessor` |
| 弱网自适应 | 🔶 | F-NET-01 | `NetworkQualityMonitor`（指标依赖 native） |
| 直接触控 / 鼠标指针模式 | ✅ | F-IN-01 | `RemoteMouseMode`, `RemoteDesktopView` |
| 触控 / 右键 / 双指滚动 | ✅ | F-IN-03 | `RemoteDesktopView`, `TouchpadView` |
| 触控板相对模式（扩展布局） | ✅ | F-IN-02 | `TouchpadView` |
| MS RDP 软键盘 + 功能键 | ✅ | F-IN-04/05 | `WindowsRemoteKeyboardPanel`, `WindowsAuxiliaryKeyboardView`, `OnScreenKeyboardView` |
| 系统键盘（中文 IME） | ✅ | F-IN-04 | `RemoteKeyboardHost` |
| 蓝牙键鼠 | ✅ | — | `MouseInputHandler`, `HardwareKeyboardHost` |
| 音频会话 / 听筒免提 | ✅ | F-AUD-05/06 | `AudioSessionManager` |
| RDP 真实连接 | ✅ | — | `NativeRDPSession`, `RDPBridge` |
| 双向音频重定向 | 🔶 | F-AUD-01/02/03 | FreeRDP audin/rdpsnd 已编入，回调待真机验证 |
| AirPlay 扩展 Scene | ✅ | F-AP-01/02/04 | `ExternalDisplayManager`, `ExternalDisplaySceneDelegate` |
| 扩展/镜像切换 | ✅ | F-AP-01/03 | `ExternalDisplayManager` |
| 触控板最大化 + 底部控件 | ✅ | F-AP-02 | `TouchpadView` |
| 自动重连 | ⏳ | F-CONN-05 | — |
| 音频向导 | ⏳ | F-AUD-09 | — |

图例：✅ 已实现 · 🔶 部分/待验证 · ⏳ 未开始

---

## 工程结构

```
app/RDPAirPlay/                    Swift 源码（应用显示名 RDP AirPlay）
  RDPAirPlayApp.swift              入口，注入 HostStore / ExternalDisplayManager
  Info.plist                       CFBundleDisplayName = RDP AirPlay
  App/
    AppDelegate.swift              外接 Scene 配置、方向
    ExternalDisplaySceneDelegate.swift   电视 UIWindow（须在 willConnect 立即创建）
  Bridge/
    RDPBridge.swift                Swift ↔ C 桥接
    RDPFrameConverter.swift        帧 → UIImage
  Input/
    HardwareKeyboardHost.swift     GCKeyboard / UIKey 映射
    HardwareKeyboardMapper.swift
    MouseInputHandler.swift        蓝牙鼠标、间接指针
  Models/                          HostProfile, ColorMode, SessionState, …
  Services/
    ExternalDisplayManager.swift   外接屏检测、扩展/镜像、帧分流
    HostStore.swift, KeychainService.swift
    ColorModeProcessor.swift, AudioSessionManager.swift
    SessionOrientationManager.swift
  Session/
    RDPSessionController.swift     会话中枢：输入、缩放、色彩、外接屏回调
    RDPSessionProtocol.swift       Native / Stub 工厂
    RemoteMouseMode.swift          directTouch / mousePointer
    StubRDPSession.swift           无 FreeRDP 时的占位会话
  Views/
    SessionView.swift              手机布局 vs 扩展布局分支
    RemoteDesktopView.swift        UIKit 远程画布（缩放、手势、光标）
    TouchpadView.swift             扩展模式触控板 + 底部键盘/功能键
    SessionConnectionBar.swift     顶部：状态、鼠标、键盘、AirPlay
    SessionToolbar.swift           底部工具栏
    Components/
      WindowsRemoteKeyboardPanel.swift    辅助键 + 修饰键 + QWERTY
      WindowsAuxiliaryKeyboardView.swift  Fn / 123 / 方向键三页
      OnScreenKeyboardView.swift
      FunctionKeyPad.swift, ModifierKeyBar.swift
      RemoteKeyboardHost.swift            系统键盘 IME
      SessionExternalDisplayHost.swift    会话内外接屏刷新
native/                            rdp_bridge C API + FreeRDP 静态库
scripts/
  generate_xcodeproj.py            扫描 Swift 文件生成 pbxproj
  build_openssl_ios.sh
  build_freerdp_ios.sh
docs/                              需求、项目说明、本文件
```

---

## 关键实现说明

### 远程桌面画布（手机直连）

文件：`Views/RemoteDesktopView.swift`

- UIKit `RemoteDesktopCanvasView` 承载画面与手势，避免 SwiftUI 缩放导致点击坐标偏移。
- **鼠标指针模式**：光标独立层渲染；双指捏合以光标为锚点缩放；1× 时单指长按拖移光标；>1× 时单指拖动平移画布。
- **直接触控模式**：触摸坐标映射到桌面；缩放以捏合点为中心。
- 支持蓝牙间接指针（`MouseInputHandler`）。

### 触控板布局（电视扩展）

文件：`Views/TouchpadView.swift`

垂直顺序（自上而下）：

1. **触控板** — `layoutPriority(1)`，`maxHeight: .infinity`，占满剩余空间。
2. **左键 / 右键** — 按住发送 mouse down/up。
3. **键盘关闭时** — `ModifierToggleBar` + 可收起 `FunctionKeyPad`。
4. **键盘打开时** — `WindowsRemoteKeyboardPanel`（与手机直连同款）；或仅 `WindowsAuxiliaryKeyboardView`（系统键盘模式）。

### AirPlay 扩展模式

文件：`Services/ExternalDisplayManager.swift`, `App/ExternalDisplaySceneDelegate.swift`

- `Info.plist` 启用 `UIApplicationSupportsMultipleScenes` 与外接 Scene Delegate。
- `ExternalDisplaySceneDelegate` 必须在 `scene:willConnectTo:` **立即**创建 `UIWindow`，否则系统可能只镜像不分配独立 Scene。
- 状态：`none` → `airplayPending`（已捕获但未拿到 Scene）→ `dedicated`（扩展成功）/ `mirrored`。
- `useExtendedLayout == true` 时 `SessionView` 切换到触控板布局；帧通过 `presentDesktopImage` / `presentCursor` 分流到电视。

真机调试建议：

1. 先进入 RDP 会话并保持 App 前台。
2. 再开 AirPlay；观察顶部 badge「接管中」→「电视扩展」。
3. 若长期「接管中」，断开重连或查看是否被系统限制外接 Scene。

### 软键盘

- **完整面板**：`WindowsRemoteKeyboardPanel` = 辅助键区 + Ctrl/Alt/Shift/Win + QWERTY。
- **辅助键三页**：Fn（F1–F12 等）、123（小键盘）、方向键页 — `WindowsAuxiliaryKeyboardView`。
- **系统键盘**：点 QWERTY 行的「123」或「中文」→ `useSystemKeyboard = true` → `RemoteKeyboardHost` 捕获 IME 输入。

---

## 运行 Stub 会话

1. 不构建 FreeRDP，或删除 `native/dist/freerdp/lib/libfreerdp3.a`。
2. 添加主机，保存后进入会话。
3. 应看到 Stub 占位画面（约 12fps）；地址 `fail.auth` / `fail.host` 可测错误路径。

## 构建 FreeRDP 并运行 Native 会话

```bash
bash scripts/build_openssl_ios.sh
bash scripts/build_freerdp_ios.sh
python3 scripts/generate_xcodeproj.py

cd app && xcodebuild -project RDPAirPlay.xcodeproj -scheme RDPAirPlay \
  -destination 'generic/platform=iOS Simulator' build
```

真机：

```bash
PLATFORM=OS64 bash scripts/build_freerdp_ios.sh
```

在 Xcode 配置 Development Team 后运行到设备。

## FreeRDP 集成检查清单

- [x] iOS 模拟器静态库（x86_64 / arm64）
- [x] iOS 真机 arm64 库
- [x] `rdp_bridge_connect`：NLA + TLS
- [x] Software GDI 帧 → Swift `UIImage`
- [x] 光标图像与位置回调
- [x] 键鼠、Unicode 文本注入
- [x] `audin-ios` / `rdpsnd-ios` 编入 libfreerdp-client3
- [ ] Display Control 动态分辨率稳定可用
- [ ] Spike：Windows 录音机电平 + 微信通话真机验收

## 新增 Swift 文件后

```bash
python3 scripts/generate_xcodeproj.py
```

脚本扫描 `app/RDPAirPlay/**/*.swift` 并更新 `project.pbxproj`。

## 需求追踪

实现 PR / commit 请在描述中引用 `docs/REQUIREMENTS.md` 中的 ID（如 `F-AUD-03`）。

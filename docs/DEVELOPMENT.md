# RDP AirPlay 开发指南

配套文档：[REQUIREMENTS.md](REQUIREMENTS.md) · [PROJECT.md](PROJECT.md) · [USER_GUIDE.md](USER_GUIDE.md) · [../README.md](../README.md)

---

## 当前进度（截至 2026-08-31）

| 模块 | 状态 | 需求 ID | 主要文件 |
|------|------|---------|----------|
| 主机列表 / 编辑 / Keychain | ✅ | F-CONN-01/02/03 | `HostListView`, `HostStore`, `KeychainService` |
| 连接状态与错误提示 | ✅ | F-CONN-04/06 | `RDPSessionController`, `RDPErrorFormatter` |
| 分辨率预设与自定义 | ✅ | F-DISP-01 | `HostProfile`, `ResolutionPreset` |
| 会话中改分辨率 | 🔶 | F-DISP-02 | `RDPBridge` 接口已有，Display Control 待完善 |
| 色彩模式 全彩/灰度/黑白 | ✅ | F-NET-02/03/04 | `ColorModeProcessor` |
| 弱网自适应（色彩 + 带宽估算） | 🔶 | F-NET-01 | `NetworkQualityMonitor`, `FrameBandwidthEstimator` |
| **弱网速度优先**（RDP 性能标志） | ✅ | F-NET-07 | `rdp_bridge_freerdp.c`, `NetworkPathObserver`, `RDPSessionController` |
| **仅电视扩展模式** | ✅ | F-AP-01/02 | `SecondScreenGuideView`, `SessionView` |
| 触控 / 右键 / 双指滚动 | ✅ | F-IN-03 | `TouchpadView` |
| 触控板相对模式（扩展布局） | ✅ | F-IN-02 | `TouchpadView` |
| MS RDP 软键盘 + 功能键 | ✅ | F-IN-04/05 | `WindowsRemoteKeyboardPanel`, `WindowsAuxiliaryKeyboardView` |
| 系统键盘（中文 IME） | ✅ | F-IN-04 | `RemoteKeyboardHost`, `SessionInputCoordinator` |
| **软键盘稳定性**（帧/IME 解耦） | ✅ | — | `SessionInputHosts`, `RDPSessionController`, native 输入队列 |
| 蓝牙键鼠 | ✅ | — | `MouseInputHandler`, `HardwareKeyboardHost` |
| 音频会话 / 听筒免提 | ✅ | F-AUD-05/06 | `AudioSessionManager` |
| RDP 真实连接 | ✅ | — | `NativeRDPSession`, `RDPBridge` |
| 远程音频播放（rdpsnd） | ✅ | F-AUD-01 | FreeRDP rdpsnd-ios |
| 远程麦克风重定向（audin） | ✅ | F-AUD-02/03 | `audin_ios.m` 补丁 + `rdp_bridge` 通道注册 |
| **会话防锁屏** | ✅ | — | `ScreenWakeLock` |
| AirPlay 扩展 Scene | ✅ | F-AP-01/02/04 | `ExternalDisplayManager`, `ExternalDisplaySceneDelegate` |
| 扩展/镜像切换 | ✅ | F-AP-01/03 | `ExternalDisplayManager` |
| 触控板最大化 + 底部控件 | ✅ | F-AP-02 | `TouchpadView` |
| 手机直连画布（遗留） | 🔶 | F-DISP-03 | `RemoteDesktopView`（主流程已移除，代码保留） |
| 自动重连 | ⏳ | F-CONN-05 | — |
| 音频向导 | ⏳ | F-AUD-09 | — |

图例：✅ 已实现 · 🔶 部分/遗留 · ⏳ 未开始

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
    RDPBridge.swift                Swift ↔ C 桥接；帧解码移出 RDP 线程
    RDPFrameConverter.swift        帧 → UIImage（image(fromCopiedPixels:)）
  Input/
    SessionInputCoordinator.swift  稳定输入层（Equatable 宿主，与帧刷新解耦）
    HardwareKeyboardHost.swift     GCKeyboard / UIKey 映射（回调模式）
    HardwareKeyboardMapper.swift
    MouseInputHandler.swift        蓝牙鼠标、间接指针
  Models/                          HostProfile, ColorMode, SessionState, …
  Services/
    ExternalDisplayManager.swift   外接屏检测、扩展/镜像、帧分流
    HostStore.swift, KeychainService.swift
    ColorModeProcessor.swift, AudioSessionManager.swift
    NetworkPathObserver.swift       蜂窝/受限网络检测
    ScreenWakeLock.swift           会话期间 UIApplication.isIdleTimerDisabled
    SessionOrientationManager.swift
  Session/
    RDPSessionController.swift     会话中枢：帧节流、弱网重连、输入、色彩、外接屏、防锁屏
    FrameBandwidthEstimator.swift  帧间隔/像素量估算带宽
    RDPSessionProtocol.swift       Native / Stub 工厂
    RemoteMouseMode.swift          directTouch / mousePointer
    StubRDPSession.swift           无 FreeRDP 时的占位会话
  Views/
    SessionView.swift              引导页 vs 触控板布局分支
    SecondScreenGuideView.swift    未连接电视时的引导 UI
    TouchpadView.swift             扩展模式触控板 + 底部键盘/功能键
    RemoteDesktopView.swift        UIKit 远程画布（遗留，非主流程）
    SessionConnectionBar.swift     顶部：状态、键盘、AirPlay
    SessionToolbar.swift           底部工具栏
    Components/
      WindowsRemoteKeyboardPanel.swift    辅助键 + 修饰键 + QWERTY
      WindowsAuxiliaryKeyboardView.swift  Fn / 123 / 方向键三页
      RemoteKeyboardHost.swift            系统键盘 IME（仅激活态变化时改 first responder）
      SessionExternalDisplayHost.swift    会话内外接屏刷新
native/                            rdp_bridge C API + FreeRDP 静态库
  src/rdp_bridge_freerdp.c         输入队列、audin/rdpsnd 通道、DeviceRedirection
  vendor/FreeRDP/                  submodule；含 audin-ios RunLoop 补丁
scripts/
  generate_xcodeproj.py            扫描 Swift 文件生成 pbxproj
  build_openssl_ios.sh
  build_freerdp_ios.sh
docs/                              需求、项目说明、用户指南、本文件
```

---

## 关键实现说明

### 仅电视扩展模式

文件：`Views/SessionView.swift`, `Views/SecondScreenGuideView.swift`

- 主流程 **不再** 在手机上显示远程桌面画布。
- 未检测到 AirPlay 扩展 Scene 时显示 `SecondScreenGuideView`（连接步骤、刷新检测）。
- RDP 可在后台保持连接；电视就绪后 `useExtendedLayout == true`，切换到 `TouchpadView`。
- 帧通过 `ExternalDisplayManager.presentDesktopImage` 分流到电视 UIKit 视图。

### 帧刷新与 SwiftUI 解耦

文件：`Session/RDPSessionController.swift`, `Bridge/RDPBridge.swift`

- `latestFrame` / `cursor` **不再** 使用 `@Published`，避免每帧触发 SwiftUI 全树重绘。
- RDP 回调线程只做像素拷贝；`UIImage` 解码在后台队列完成。
- 电视输出 **20fps 节流**；`UIUpdateCoalesceBuffer` 合并 UI 更新。
- 这是修复系统软键盘 IME 闪退（Watchdog `0x8BADF00D`）的核心措施之一。

### 稳定输入层

文件：`Input/SessionInputCoordinator.swift`, `Views/Components/RemoteKeyboardHost.swift`

- `SessionInputHosts` 实现 `Equatable`，仅在激活态变化时重建 IME 宿主。
- `RemoteKeyboardHost.updateUIView` 不再随帧刷新抢 first responder。
- 键盘回调 deferred 到下一 RunLoop，避免在 UIKit 更新周期内同步发送 RDP 输入。

### Native 输入队列

文件：`native/src/rdp_bridge_freerdp.c`

- 键鼠/Unicode 从任意线程 **入队**，RDP 线程 **drain** 后发送。
- Unicode 文本发送按下 + 释放事件对。
- 队列上限 512，防止积压导致内存问题。

### 会话防锁屏

文件：`Services/ScreenWakeLock.swift`, `Session/RDPSessionController.swift`

- 连接成功时 `ScreenWakeLock.acquire()` → `UIApplication.shared.isIdleTimerDisabled = true`。
- 断开/销毁时 `release()` 恢复系统默认。

### 麦克风重定向（audin-ios）

文件：`native/vendor/FreeRDP/channels/audin/client/ios/audin_ios.m`（**本地补丁**）

- **根因**：FreeRDP 会话跑在无 RunLoop 的 RDP 线程；原 `AudioQueueNewInput` 绑该线程导致采集失败。
- **修复**：`AudioQueueNewInput` 改用 `CFRunLoopGetMain()`。
- `rdp_bridge_freerdp.c` 在启用麦克风时注册 `audin` + `ios` 子通道，并开启 `DeviceRedirection`。
- `AudioSessionManager` 连接前请求麦克风权限，配置 `playAndRecord` + `voiceChat`。

Windows 端需允许 **音频录制重定向**（组策略或 RDS 集合）；远程输入设备应出现 Remote Audio。

### 弱网速度优先（RDP Performance Flags）

文件：`native/src/rdp_bridge_freerdp.c`, `Services/NetworkPathObserver.swift`, `Session/RDPSessionController.swift`

- `rdp_bridge_config.optimize_for_speed` 为 1 时，通过 FreeRDP 设置 `DisableWallpaper`、`DisableFullWindowDrag`、`DisableMenuAnims`、`DisableThemes` 等，并调用 `freerdp_performance_flags_make()`。
- **连接时**：`NetworkPathObserver` 检测蜂窝 / 低数据 / 昂贵网络 → 速度优先；Wi‑Fi 默认画质优先。
- **会话中**：`FrameBandwidthEstimator` 估算码率；低档持续约 6 秒后 **自动重连** 以应用性能标志（RDP 仅在握手时协商）。
- 会话设置 **网络** 区展示「速度优先 / 画质优先」状态。

### 触控板布局（电视扩展）

文件：`Views/TouchpadView.swift`

垂直顺序（自上而下）：

1. **触控板** — `layoutPriority(1)`，`maxHeight: .infinity`，占满剩余空间。
2. **左键 / 右键** — 按住发送 mouse down/up。
3. **键盘关闭时** — `ModifierToggleBar` + 可收起 `FunctionKeyPad`。
4. **键盘打开时** — `WindowsRemoteKeyboardPanel`；或 `WindowsAuxiliaryKeyboardView`（系统键盘模式）。

### AirPlay 扩展 Scene

文件：`Services/ExternalDisplayManager.swift`, `App/ExternalDisplaySceneDelegate.swift`

- `Info.plist` 启用 `UIApplicationSupportsMultipleScenes` 与外接 Scene Delegate。
- `ExternalDisplaySceneDelegate` 必须在 `scene:willConnectTo:` **立即**创建 `UIWindow`。
- 状态：`none` → `airplayPending` → `dedicated` / `mirrored`。
- 帧通过 `presentDesktopImage` / `presentCursor` 分流到电视。

真机调试建议：

1. 先进入 RDP 会话并保持 App 前台。
2. 再开 AirPlay；观察状态由「接管中」→「电视扩展」。
3. 若长期停在引导页，断开 AirPlay 重连或点 **刷新检测**。

---

## 运行 Stub 会话

1. 不构建 FreeRDP，或删除 `native/dist/freerdp/lib/libfreerdp3.a`。
2. 添加主机，保存后进入会话。
3. 应看到 Stub 占位画面；地址 `fail.auth` / `fail.host` 可测错误路径。

## 构建 FreeRDP 并运行 Native 会话

```bash
bash scripts/build_openssl_ios.sh
bash scripts/build_freerdp_ios.sh                    # 模拟器
IOS_PLATFORM=OS64 bash scripts/build_freerdp_ios.sh  # 真机（含 audin 补丁）
python3 scripts/generate_xcodeproj.py

cd app && xcodebuild -project RDPAirPlay.xcodeproj -scheme RDPAirPlay \
  -destination 'generic/platform=iOS Simulator' build
```

真机：在 Xcode 配置 Development Team 后运行到设备。**修改 audin 补丁后必须重建真机库。**

## FreeRDP 集成检查清单

- [x] iOS 模拟器静态库（x86_64 / arm64）
- [x] iOS 真机 arm64 库
- [x] `rdp_bridge_connect`：NLA + TLS
- [x] Software GDI 帧 → Swift `UIImage`（解码不在 RDP/UI 线程）
- [x] 光标图像与位置回调
- [x] 键鼠、Unicode 文本注入（线程安全输入队列）
- [x] `audin-ios` RunLoop 补丁 + `rdpsnd-ios` 编入 libfreerdp-client3
- [x] 连接前麦克风权限与 AVAudioSession 配置
- [x] 会话期间 ScreenWakeLock
- [ ] Display Control 动态分辨率稳定可用
- [ ] 微信通话全链路真机验收（AC-05、AC-06）

## 新增 Swift 文件后

```bash
python3 scripts/generate_xcodeproj.py
```

脚本扫描 `app/RDPAirPlay/**/*.swift` 并更新 `project.pbxproj`。

## 需求追踪

实现 PR / commit 请在描述中引用 `docs/REQUIREMENTS.md` 中的 ID（如 `F-AUD-03`）。

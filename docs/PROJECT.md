# RDP AirPlay 项目说明文档

版本：1.2  
日期：2026-08-31  
配套需求：[REQUIREMENTS.md](REQUIREMENTS.md)  
仓库入口：[../README.md](../README.md)

---

## 1. 项目定位

**RDP AirPlay**（仓库名 `RDPAirPlay`）是面向 iOS 的远程桌面控制产品，协议采用 Microsoft RDP，被控端为用户本机或办公 Windows。产品差异化不在「再做一个远程桌面」，而在几件事同时成立：

- **必须连接 AirPlay 电视**：电视看桌面，手机当大触控板 + 软键盘
- **最差网络**下通过降分辨率、降帧、灰度/黑白仍能完成点击
- **双向音频**足够支撑远程微信等应用的接听与通话
- **系统软键盘稳定**：中文 IME 不因 RDP 帧刷新而闪退

本说明描述「为什么做、怎么拆、怎么验、有什么坑」。需求条目、优先级与验收用例以需求文档为准。

## 2. 当前实现快照（0.1.0）

以下能力已在代码中落地，供与需求 ID 对照：

| 领域 | 已实现 | 待完善 |
|------|--------|--------|
| 连接 | 主机列表、Keychain、NLA、FreeRDP Native/Stub | 自动重连 |
| 显示 | 电视扩展帧分流、色彩模式 | Display Control 分辨率 |
| 输入 | 触控板、软键盘、功能键、蓝牙键鼠、IME 稳定层 | — |
| 扩展屏 | SceneDelegate 外接窗、引导页、触控板布局 | 全机型真机验收 |
| 弱网 | 全彩/灰度/黑白、锁定、NetworkQualityMonitor | native 指标驱动降档 |
| 音频 | rdpsnd 播放、audin-ios 麦克风重定向、AVAudioSession | 微信全链路验收 |
| 会话 | ScreenWakeLock 防锁屏 | 后台通话（P2） |

应用 **显示名称** 为 `RDP AirPlay`（`Info.plist` `CFBundleDisplayName`）；Xcode Target / 模块名仍为 `RDPAirPlay`。

**产品模式变更（0.1.0）：** 主流程仅支持 **电视扩展模式**；未连接电视时显示引导页，不在手机上直接操作远程桌面。

## 3. 要解决的问题

| 痛点 | 产品回应 |
|------|----------|
| 出门无法操作家里/公司电脑 | 标准 RDP 客户端，保存主机与凭据 |
| 手机屏小、要给旁人看桌面 | AirPlay **扩展**（必需）：电视看桌面，手机当触控板 |
| 地铁、弱 4G 花屏卡死 | 自适应码率 + 灰度/黑白锁定 |
| 电脑挂着微信，来电接不到 | 远程点接听 + 麦克风/扬声器重定向 |
| 中文软键盘用着闪退 | 帧刷新与 IME 解耦、native 输入队列 |
| 会话中自动锁屏打断通话 | ScreenWakeLock 保持常亮 |

不解决：未授权入侵、替代运营商电话、把微信变成 CallKit 原生来电、第一期做全平台被控端。

## 4. 成功标准（项目级）

项目在 P0 结束时视为「技术闭环成立」，当且仅当：

1. 测试机 Windows 上微信来电，iOS 能听到铃声。  
2. 用户在电视画面所对应的远程桌面上点接听（手机触控板操作）。  
3. 对方能听到 iOS 麦克风（Windows 输入设备为 Remote Audio）；用户能听到对方；可持续对话至挂断。  
4. 系统软键盘连续中文输入不闪退。  
5. 同一版本在人为弱网下，灰度或黑白模式仍能完成该点击。

AirPlay 扩展 UI 与触控板已实现；P1 验收重点转为 **真机全链路**（Scene 分配、弱网、微信通话）。若第 3 条因 Windows 组策略禁止录音重定向失败，需在一周内给出 Agent/虚拟声卡的 P1 方案。

## 5. 技术方案摘要

### 5.1 控制面

Swift 管理主机列表、连接参数、色彩锁定、分辨率、外接屏布局。密码只进 Keychain。会话中枢为 `RDPSessionController`（帧节流、防锁屏、音频权限）。

### 5.2 数据面

FreeRDP 3.x 经 `rdp_bridge` C API 接入 Swift：

- 图形（Software GDI → RGBA 帧，解码不在 RDP/UI 线程）
- 键盘鼠标、Unicode（线程安全输入队列）
- 下行/上行音频通道（audin-ios 含 RunLoop 补丁、rdpsnd-ios）
- Display Control（接口已有）

Swift 与 C 边界：会话创建/销毁、帧回调、光标回调、输入注入、错误码映射。

### 5.3 弱网

阶梯（实现中，数值可标定）：

1. 降帧（电视输出 20fps 节流）  
2. 降分辨率  
3. 全彩 → 灰度 → 黑白  
4. 提高量化 / 降低色深  

用户可锁定色彩模式（底部工具栏「全彩」菜单）。

### 5.4 AirPlay 与第二屏

**已实现路径：**

1. `Info.plist` 声明多 Scene + `UIWindowSceneSessionRoleExternalDisplayNonInteractive`。  
2. `ExternalDisplaySceneDelegate` 在 `willConnect` 立即创建 `UIWindow`。  
3. `ExternalDisplayManager` 检测 Scene 连接，状态：`airplayPending` → `dedicated` / `mirrored`。  
4. **未连接电视**：`SecondScreenGuideView` 引导用户 AirPlay。  
5. **扩展模式**：电视 `ExternalDesktopViewController` 显示远程帧；手机 `TouchpadView`。  
6. 同一解码结果分流到电视，**禁止**为投屏再拉一路 RDP。

### 5.5 输入与交互

**电视扩展（`TouchpadView`，主流程）：**

- 单指相对移动指针；点按左键；长按右键；双指滚动。  
- 布局：触控板最大化，左/右键与键盘/功能键沉底。

**软键盘：** MS RDP 三页辅助键 + 修饰键 + QWERTY；可切系统键盘输入中文。`SessionInputCoordinator` 保证 IME 宿主不随帧刷新重建。

**硬件：** 蓝牙鼠标/触控板（间接指针）、外接键盘（GCKeyboard 映射）。

**遗留：** `RemoteDesktopView` 手机直连画布代码仍保留，但已从主流程移除。

### 5.6 音频会话

- 连接前请求麦克风权限；无权限时明确报错。
- 办公听声：播放类别；开麦后切 `playAndRecord` + `voiceChat`（系统 AEC）。
- audin-ios：`AudioQueueNewInput` 绑主 RunLoop（FreeRDP 补丁）。
- Windows 需允许音频录制重定向；远程输入设备选 Remote Audio。
- P0：前台保活 + ScreenWakeLock；进后台提示通话可能中断。

## 6. 关键路径与风险

| 风险 | 影响 | 缓解 |
|------|------|------|
| 远程会话无可用麦克风 | 微信对方完全听不到 | audin RunLoop 补丁；Windows 组策略；Spike 验收 |
| RDP 帧驱动 SwiftUI 重绘 | 软键盘 IME 闪退 | 帧非 @Published、输入层 Equatable、20fps 节流 |
| 外接 Scene 未分配 | 只能镜像不能扩展 | SceneDelegate 立即建窗；引导页 + 刷新检测 |
| iOS 杀后台 | 锁屏/后台通话中断 | ScreenWakeLock + 说明；P2 后台音频 |
| FreeRDP 许可与 App Store | 上架受阻 | 保留许可证声明 |
| 双屏双编码 | 弱网更差 | 单路帧分流（已实现） |

**强制 Spike（音频）**

- 环境：Win11 + RDP + 微信 + 允许录音重定向  
- 动作：iOS 连接并开麦克风重定向  
- 记录：远程录音设备、电平、微信通话  
- 产出：通过 / 失败 / 是否需 Agent  

## 7. 里程碑

| 阶段 | 状态 | 产出 |
|------|------|------|
| M0 Spike | 🔶 | 音频重定向（audin 补丁已合，待微信验收） |
| M1 连上 | ✅ | 画面、键盘、存主机 |
| M2 画质 | ✅ | 分辨率预设、灰度/黑白 |
| M3 声音 | ✅ 代码完成 | rdpsnd + audin-ios + 权限流程 |
| M4 通话验收 | ⏳ | AC-05、AC-06 |
| M5 AirPlay | ✅ | 仅扩展模式、引导页、触控板、帧分流 |
| M5b 输入稳定 | ✅ | IME 解耦、输入队列、防锁屏 |
| M6 打磨 | 持续 | 重连、向导、错误文案 |

## 8. 工程与质量

- 语言：Swift 5/6 + C 桥接（`RDPBridge`）。  
- 最低系统：iOS 16。  
- 应用显示名：**RDP AirPlay**。  
- FreeRDP submodule 含 **audin-ios 本地补丁**；重建真机库后需重新安装 App。  
- 日志：连接阶段可记主机与错误码；禁止默认记录密码与桌面内容。  
- 测试：真机必测麦克风、AirPlay、软键盘中文输入、蓝牙键鼠；模拟器不能作为音频/外接屏验收环境。  

## 9. 发布与合规

- Info.plist 麦克风、本地网络用途与真实行为一致。  
- 隐私政策：音视频仅在用户发起的 RDP 会话中传输到用户指定主机。  
- 第三方库许可证随包或随仓库提供。  

## 10. 文档维护

| 变更类型 | 改需求文档 | 改本说明 | 改用户说明 |
|----------|------------|----------|------------|
| 增删功能、验收、优先级 | 是 | 必要时同步 | 是 |
| 架构、风险、里程碑 | 否 | 是 | 否 |
| 界面操作、手势、AirPlay 步骤 | 否 | 否 | [USER_GUIDE.md](USER_GUIDE.md) |
| 开发进度、构建步骤 | — | — | [DEVELOPMENT.md](DEVELOPMENT.md) |

## 11. 变更记录

| 版本 | 日期 | 说明 |
|------|------|------|
| 1.0 | 2026-08-30 | 初稿 |
| 1.1 | 2026-08-30 | 同步 0.1.0 实现：外接 Scene、触控板、MS RDP 输入、应用更名 RDP AirPlay |
| 1.2 | 2026-08-31 | 仅电视扩展模式、软键盘/IME 稳定、ScreenWakeLock、audin-ios RunLoop 补丁、麦克风权限流程 |

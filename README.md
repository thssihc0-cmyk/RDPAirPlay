# RDP AirPlay

iOS 远程桌面客户端（仓库名 `RDPAirPlay`）：通过 RDP 控制 Windows，**需连接 AirPlay 电视** 进行触控与键盘操作；支持 Microsoft Remote Desktop 风格软键盘、可调分辨率、弱网灰度/黑白，以及双向音频（含远程微信接听场景）。

- 需求（范围、功能 ID、验收）：[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- 说明（架构、风险、里程碑）：[docs/PROJECT.md](docs/PROJECT.md)
- 开发（进度、构建、目录）：[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- **使用（连接、AirPlay、键盘、音频）：[docs/USER_GUIDE.md](docs/USER_GUIDE.md)**

---

## 项目是什么

**RDP AirPlay** 是跑在 iPhone / iPad（iOS 16+）上的 RDP 客户端。用户添加 Windows 主机并登录后，将画面 **AirPlay 到电视**；电视显示远程桌面，手机变为 **大触控板 + 软键盘**。

与「只能看屏幕」的工具不同，本项目把下面几件事写进同一产品：

1. **电视扩展（必需）**：AirPlay 后电视独立显示远程桌面，手机当触控板；未连接电视时显示引导页，RDP 可在后台保持连接。
2. **MS RDP 风格操作**：大触控板、双指滚动、完整软键盘与功能键、系统中文 IME。
3. **画质可降**：网络差时切灰度或黑白，优先保证能点到按钮。
4. **声音双向**：远程系统声与应用声播放；iOS 麦克风经 RDP audin 重定向到 Windows，供微信等应用采集。
5. **远程接电话**：电脑上微信来电，在 iOS 上点接听——走「远程桌面 + 麦克风/扬声器重定向」，不是 CallKit 系统电话。
6. **会话保活**：远程连接期间禁止自动锁屏，避免通话与输入中断。

被控端为用户自己的 Windows 10/11（已开启远程桌面）。第一期不强制安装自研 Windows Agent。

## 当前版本能力（0.1.0）

| 能力 | 状态 |
|------|------|
| 主机列表、Keychain 存密码、NLA 连接 | ✅ |
| FreeRDP 真连接（无库时回退 Stub） | ✅ |
| **仅电视扩展模式**（无电视 → 引导页） | ✅ |
| 触控板最大化 + 底部左/右键与 MS RDP 软键盘 | ✅ |
| 系统软键盘（中文 IME）与蓝牙键鼠 | ✅ |
| 全彩 / 灰度 / 黑白 + 弱网自动降档 | ✅ |
| AirPlay 扩展 Scene（电视桌面 + 手机触控板） | ✅ |
| 远程音频播放（rdpsnd） | ✅ 真机已验证 |
| 远程麦克风重定向（audin-ios） | ✅ 已实现（需 iOS 授权 + Windows 允许录制重定向） |
| 会话期间禁止自动锁屏 | ✅ |
| 软键盘稳定性（帧刷新与 IME 解耦、输入队列） | ✅ |
| 会话中分辨率修改（Display Control） | 🔶 接口已有，待 native 完善 |
| 自动重连、音频向导 | ⏳ P1 |

图例：✅ 已实现 · 🔶 部分完成 · ⏳ 计划中

## 为什么要单独说明「微信接听」

微信语音走应用内 VoIP，不走 iOS CallKit。手机上的「接听」是去点远程窗口里的按钮；对方听到的是 **Windows 会话里的那个麦克风**。因此项目是否成功，取决于 RDP **音频输入重定向（audin）** 是否真正出现在远程会话里。

约束（实现时必须遵守）：

- 通话期间 App 保持前台（iOS 后台会停麦）。会话期间已禁用 idle 锁屏。
- Windows 需允许 **音频录制重定向**（组策略 / RDS 集合）；远程「输入设备」中应出现 Remote Audio。
- 只连接用户有权使用的主机，不做未授权访问。

## 文档索引

| 文档 | 内容 |
|------|------|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | **用户使用说明**：连接、AirPlay、键盘、音频、常见问题 |
| [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) | 产品需求：范围、功能 ID、非功能、分期、验收用例 |
| [docs/PROJECT.md](docs/PROJECT.md) | 项目说明：定位、架构、风险、里程碑、工程与合规 |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 开发指南：当前进度、工程结构、构建步骤 |
| 本文（README） | 仓库入口：产品概述、当前能力、快速开始 |

## 目标平台

| 端 | 要求 |
|----|------|
| 控制端 | iOS 16+，iPhone、iPad；应用显示名 **RDP AirPlay** |
| 被控端 | Windows 10 21H2 或更新 / Windows 11，已启用 RDP（默认 3389） |
| 网络 | IPv4，TCP；后期可加 RDP UDP |
| 投屏 | **AirPlay（Apple TV 等）必需**，用于扩展模式交互 |

## 会话界面

### 未连接电视（引导页）

- 显示连接步骤、AirPlay 状态与「刷新检测」。
- RDP 可在后台保持连接；电视就绪后自动切换触控板布局。

### 电视扩展（AirPlay 扩展模式）

- **电视**：独立 `UIWindow` 全屏显示远程 Windows 桌面。
- **手机**：大触控板 + 底部左/右键 + MS RDP 软键盘（F 键、修饰键、QWERTY、系统 IME）。
- **手势**：单指移动指针、点按左键、长按右键、双指滚动。
- **工具栏**：键盘、AirPlay、横竖屏、色彩模式、设置、断开。

## 逻辑架构

```
┌─────────────────────────────────────┐
│  iOS（SwiftUI + UIKit）               │
│  会话控制 / 输入 / 弱网 / AirPlay 分流  │
│  ScreenWakeLock · SessionInputHosts   │
└─────────────────┬───────────────────┘
                  │ rdp_bridge（C）
                  │ FreeRDP 3.x + audin-ios / rdpsnd-ios
                  │ 线程安全输入队列 · 主线程帧投递
┌─────────────────▼───────────────────┐
│  Windows 远程桌面服务                 │
│  桌面、微信及其他应用                  │
└─────────────────────────────────────┘
                  │
         AirPlay 扩展 Scene（必需）
                  ▼
              电视第二屏
```

| 层 | 职责 |
|----|------|
| 界面 | 主机列表、引导页、触控板、软键盘、工具条 |
| 会话 | `RDPSessionController`：连接、输入、色彩、帧节流、外接屏回调 |
| 协议 | `RDPBridge` / FreeRDP：图形帧、光标、键鼠、audin/rdpsnd |
| 外接屏 | `ExternalDisplayManager`：扩展 Scene、帧分流 |
| 媒体 | `AudioSessionManager`（权限 + playAndRecord）、`ScreenWakeLock` |
| 输入 | `SessionInputCoordinator`：与帧刷新解耦的 IME 宿主 |

## 技术选型

| 用途 | 选型 | 说明 |
|------|------|------|
| RDP | FreeRDP 3.x + `rdp_bridge` C API | 含 **audin-ios 补丁**（AudioQueue 绑主 RunLoop） |
| UI | SwiftUI + UIKit | 远程帧不驱动 SwiftUI 全树重绘；电视用 UIKit 刷帧 |
| 外接屏 | `UIWindowSceneSessionRoleExternalDisplayNonInteractive` | SceneDelegate 在 `willConnect` 立即建窗 |
| 音频 | AVAudioSession + audin-ios | 连接前请求麦克风权限 |
| 密钥 | Keychain | 密码不进 plist / UserDefaults |

## 快速开始（开发）

```bash
# 1. 构建 native 库（模拟器 + 真机）
bash scripts/build_openssl_ios.sh
bash scripts/build_freerdp_ios.sh                    # 模拟器
IOS_PLATFORM=OS64 bash scripts/build_freerdp_ios.sh  # 真机（含 audin 补丁）

# 2. 生成 / 更新 Xcode 工程
python3 scripts/generate_xcodeproj.py

# 3. 打开工程并在 Xcode 中选择 Development Team 后运行到真机
open app/RDPAirPlay.xcodeproj
```

若 `native/dist/freerdp/lib/` 下存在对应平台的库，应用自动使用 `NativeRDPSession` 连接真实 Windows 主机；否则回退 Stub 模式。

### AirPlay 电视扩展（使用步骤）

1. 进入远程会话，保持 App 在前台。
2. 控制中心 → 屏幕镜像 → 选择电视。
3. 返回 App，状态由「接管中」变为「电视扩展」。
4. 电视显示远程桌面；手机变为触控板布局。
5. 若长期停在引导页，断开 AirPlay 后重连，或点 **刷新检测**。

## 仓库目录

```
app/RDPAirPlay/              Swift 源码（显示名 RDP AirPlay）
  Input/                     SessionInputCoordinator、硬件键盘
  Services/                  外接屏、音频、ScreenWakeLock
  Session/                   RDPSessionController、Native/Stub
  Views/                     SessionView、TouchpadView、SecondScreenGuideView
native/                      rdp_bridge + FreeRDP（含 audin-ios 补丁）
scripts/                     构建脚本、Xcode 工程生成
docs/                        需求、项目说明、开发指南、用户指南
```

## 开发原则

1. **先打通麦克风再铺 UI**：Windows「输入设备」里应出现 Remote Audio，再用微信验证。
2. **第二屏不要双倍编码**：同一路远程帧，电视与内部分流展示。
3. **IME 与帧刷新解耦**：系统软键盘宿主不得随 RDP 帧 updateUIView。
4. **输入线程安全**：键鼠/文本经 native 输入队列在 RDP 线程发送。
5. **安全默认**：NLA、Keychain、最小权限文案。

## 验证与测试

核心路径：

1. AirPlay 扩展：电视桌面 + 手机触控板
2. 系统软键盘连续中文输入不闪退
3. 远程出声 + 麦克风重定向（Windows 输入设备可见 Remote Audio）
4. 微信来电：闻铃 → 接听 → 全双工
5. 弱网灰度/黑白仍可操作
6. 会话期间不自动锁屏

## 分期一览

- **P0**：连上、电视扩展、能听、能说（含微信）、软键盘稳定。
- **P1**：自动重连、音频向导、Display Control 完善。
- **P2**：网关、文件/剪贴板、多屏、后台通话。

细节与验收表以 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) 为准。

## 许可与使用

应用仅用于控制你拥有或被明确授权管理的计算机。嵌入的第三方库遵循其各自许可证；FreeRDP 以 git submodule 形式引用，含本地 audin-ios 补丁。

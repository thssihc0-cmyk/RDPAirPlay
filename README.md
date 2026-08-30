# RDP AirPlay

iOS 远程桌面客户端（仓库名 `RDPAirPlay`）：通过 RDP 控制 Windows，支持 AirPlay 电视扩展、Microsoft Remote Desktop 风格触控与键盘、可调分辨率、弱网灰度/黑白，以及双向音频（含远程微信接听场景）。

- 需求（范围、功能 ID、验收）：[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)
- 说明（架构、风险、里程碑）：[docs/PROJECT.md](docs/PROJECT.md)
- 开发（进度、构建、目录）：[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)
- **使用（连接、手势、AirPlay、键盘）：[docs/USER_GUIDE.md](docs/USER_GUIDE.md)**

---

## 项目是什么

**RDP AirPlay** 是跑在 iPhone / iPad（iOS 16+）上的 RDP 客户端。用户添加 Windows 主机并登录后，可在手机上看到并操作远程桌面；连接 AirPlay 电视后，电视显示桌面，手机变为触控板。

与「只能看屏幕」的工具不同，本项目把下面几件事写进同一产品：

1. **电视扩展**：AirPlay 后电视独立显示远程桌面，手机当触控板（非简单镜像）。
2. **MS RDP 风格操作**：直接触控 / 鼠标指针双模式、双指缩放与滚动、完整软键盘与功能键。
3. **画质可降**：网络差时切灰度或黑白，优先保证能点到按钮。
4. **声音双向**：远程系统声与应用声播放；iOS 麦克风重定向到远程，供微信等应用采集。
5. **远程接电话**：电脑上微信来电，在 iOS 上点接听——走「远程桌面 + 麦克风/扬声器重定向」，不是 CallKit 系统电话。

被控端为用户自己的 Windows 10/11（已开启远程桌面）。第一期不强制安装自研 Windows Agent。

## 当前版本能力（0.1.0）

| 能力 | 状态 |
|------|------|
| 主机列表、Keychain 存密码、NLA 连接 | ✅ |
| FreeRDP 真连接（无库时回退 Stub） | ✅ |
| 手机直连：远程桌面画面 + 双指缩放（1×–4×） | ✅ |
| 鼠标指针 / 直接触控模式切换 | ✅ |
| 指针模式以光标为中心缩放；放大后才允许拖动画布 | ✅ |
| MS RDP 风格软键盘（F 键、修饰键、QWERTY、系统键盘） | ✅ |
| 蓝牙键鼠（间接指针、硬件键盘映射） | ✅ |
| 全彩 / 灰度 / 黑白 + 弱网自动降档 | ✅ |
| AirPlay 扩展模式（电视桌面 + 手机触控板） | ✅ |
| 触控板最大化布局、底部左/右键与键盘 | ✅ |
| 会话中分辨率修改（Display Control） | 🔶 接口已有，待 native 完善 |
| RDP 双向音频（听 + 说） | 🔶 库已编入，回调待真机验证 |
| 自动重连、音频向导 | ⏳ P1 |

图例：✅ 已实现 · 🔶 部分完成 · ⏳ 计划中

## 为什么要单独说明「微信接听」

微信语音走应用内 VoIP，不走 iOS CallKit。手机上的「接听」是去点远程窗口里的按钮；对方听到的是 **Windows 会话里的那个麦克风**。因此项目是否成功，取决于 RDP **音频输入重定向** 是否真正出现在远程会话里。

约束（实现时必须遵守）：

- 通话期间 App 保持前台（iOS 后台会停麦）。不承诺运营商电话级延迟。
- 部分电脑默认录音设备仍是本机空麦，需要设置向导或后续 Agent。
- 只连接用户有权使用的主机，不做未授权访问。

## 文档索引

| 文档 | 内容 |
|------|------|
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | **用户使用说明**：连接、手势、键盘、AirPlay、常见问题 |
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
| 投屏 | AirPlay（Apple TV 等）或系统外接 `UIScreen` |

## 会话界面（两种布局）

### 手机直连（无电视扩展）

- 全屏远程桌面（UIKit 画布，保持宽高比）。
- 顶部连接栏：连接状态、鼠标模式、键盘、AirPlay。
- 底部工具栏：键盘、鼠标模式、AirPlay、横竖屏、色彩模式、设置、断开。
- 打开键盘后显示 MS RDP 风格完整软键盘；关闭时显示修饰键快捷栏。

**鼠标指针模式**（默认）：单击在光标处点击；长按拖移光标；双指滚动；双指捏合缩放（指针模式下以光标为锚点）；仅放大（>1×）后可单指拖动画布。

**直接触控模式**：点哪打哪；缩放以捏合中心为锚点。

### 电视扩展（AirPlay 扩展模式）

- 电视：独立 `UIWindow` 全屏显示远程桌面（`ExternalDisplaySceneDelegate`）。
- 手机：大触控板 + 底部操作区。
  - 触控板占满中间全部剩余空间。
  - 底部依次为：左键 / 右键 → 功能键或完整键盘（与手机直连同款布局）。
- 触控板手势：单指滑动移动指针、点按左键、长按右键、双指滚动。

## 逻辑架构

```
┌─────────────────────────────────────┐
│  iOS（SwiftUI + UIKit 画布）          │
│  会话控制 / 输入 / 弱网 / AirPlay 分流  │
└─────────────────┬───────────────────┘
                  │ rdp_bridge（C）
                  │ FreeRDP 3.x
                  │ 图形 · 输入 · 音频通道
┌─────────────────▼───────────────────┐
│  Windows 远程桌面服务                 │
│  桌面、微信及其他应用                  │
└─────────────────────────────────────┘
                  │
         AirPlay 扩展 Scene（可选）
                  ▼
              电视第二屏
```

| 层 | 职责 |
|----|------|
| 界面 | 主机列表、会话、远程画布、触控板、软键盘、工具条 |
| 会话 | `RDPSessionController`：连接、重连、缩放视口、输入、色彩 |
| 协议 | `RDPBridge` / FreeRDP：图形帧、光标、键鼠、分辨率 |
| 外接屏 | `ExternalDisplayManager`：扩展/镜像、Scene 接管、帧分流 |
| 媒体 | `ColorModeProcessor`、AVAudioSession |
| 弱网 | `NetworkQualityMonitor`：码率/RTT/丢包 → 色彩与档位 |

## 技术选型

| 用途 | 选型 | 说明 |
|------|------|------|
| RDP | FreeRDP 3.x + `rdp_bridge` C API | 模拟器/真机静态库；GFX、音频通道已链接 |
| UI | SwiftUI + UIKit 画布 | 远程桌面与触控板用 UIKit 手势，避免 SwiftUI 缩放坐标偏移 |
| 外接屏 | `UIWindowSceneSessionRoleExternalDisplayNonInteractive` | 须 SceneDelegate 在 `willConnect` 立即建窗 |
| 音频 | AVAudioEngine / AVAudioSession | `playAndRecord` + voice processing |
| 密钥 | Keychain | 密码不进 plist / UserDefaults |

## 快速开始（开发）

```bash
# 1. 构建 native 库（模拟器 + 真机）
bash scripts/build_openssl_ios.sh
bash scripts/build_freerdp_ios.sh                    # 模拟器（随 Mac 架构 x86_64/arm64）
PLATFORM=OS64 bash scripts/build_freerdp_ios.sh    # 真机 arm64

# 2. 生成 / 更新 Xcode 工程
python3 scripts/generate_xcodeproj.py

# 3. 打开工程并在 Xcode 中选择 Development Team 后运行到真机
open app/RDPAirPlay.xcodeproj

# 命令行编译（真机需先在 Xcode 配置签名）
cd app && xcodebuild -project RDPAirPlay.xcodeproj -scheme RDPAirPlay \
  -destination 'generic/platform=iOS Simulator' build
```

若 `native/dist/freerdp/lib/` 下存在对应平台的库，应用自动使用 `NativeRDPSession` 连接真实 Windows 主机；否则回退 Stub 模式（12fps 占位画面）。

### AirPlay 电视扩展（使用步骤）

1. 进入远程会话，保持 App 在前台。
2. 控制中心 → 屏幕镜像 → 选择电视。
3. 返回 App，顶部应显示「接管中」→「电视扩展」。
4. 电视显示远程桌面；手机变为触控板布局。
5. 若一直停留在「接管中」，断开 AirPlay 后重连，或确认 iOS 已分配外接 Scene（见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)）。

可在会话设置或 AirPlay 菜单中切换扩展/镜像；断开第二屏后画面回到手机，RDP 不断开。

## 仓库目录

```
app/RDPAirPlay/              Swift 源码与 Xcode 工程（显示名 RDP AirPlay）
  App/                       AppDelegate、ExternalDisplaySceneDelegate
  Bridge/                    RDPBridge、RDPFrameConverter
  Input/                     硬件键盘、蓝牙鼠标
  Models/                    主机、分辨率、色彩、错误
  Services/                  Keychain、HostStore、外接屏、音频、色彩
  Session/                   控制器、ScanCode、Stub/Native 会话
  Views/                     会话 UI、触控板、软键盘组件
native/                      rdp_bridge C API + FreeRDP 构建产物
scripts/                     构建脚本、Xcode 工程生成
docs/                        需求、项目说明、开发指南
```

## 开发原则

1. **先打通麦克风再铺 UI**：远程「声音设置」里能否看到随 iOS 麦跳动的输入电平，再用微信验证。
2. **弱网以可点为准**：黑白/灰度是正式功能，不是调试滤镜。
3. **第二屏不要双倍编码**：同一路远程帧，主屏与 AirPlay 只做展示分流。
4. **安全默认**：NLA、Keychain、最小权限文案；无操作内容上报。
5. **需求可追踪**：实现与 Issue 引用 `F-*`、`NF-*`、`AC-*` 编号。

## 验证与测试

开发与提测按 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) 第 10 节用例执行，核心路径：

1. 局域网全彩办公操作（含鼠标指针模式缩放与拖动画布）
2. 弱网条件下灰度/黑白仍可点击
3. 会话中改分辨率
4. 远程出声
5. 微信来电：闻铃 → 接听 → 全双工 → 挂断会话仍在
6. AirPlay 扩展：电视桌面 + 手机触控板；断开后恢复手机布局

被控端准备：Windows 开启远程桌面、账户允许远程登录、防火墙放行 3389、测试机安装微信并登录。

## 分期一览

- **P0**：连上、看清/能点、能听、能说（含微信）。
- **P1**：AirPlay 完善、重连、音频向导。（AirPlay 扩展 UI 与触控板已实现，待真机全面验收）
- **P2**：网关、文件/剪贴板、多屏、后台通话、更低延迟通道。

细节与验收表以 [docs/REQUIREMENTS.md](docs/REQUIREMENTS.md) 为准。

## 许可与使用

应用仅用于控制你拥有或被明确授权管理的计算机。嵌入的第三方库遵循其各自许可证；本仓库许可文件将在工程初始化时补充。

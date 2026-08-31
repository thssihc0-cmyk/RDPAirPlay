# 参考比较文档

> 来源：「iOS 远程桌面客户端（RDP Client）产品需求文档 (PRD)」  
> **说明：本文档仅供功能对照参考，不作为本仓库的开发需求与验收依据。** 正式需求见 [REQUIREMENTS.md](REQUIREMENTS.md)。

## 1. 项目概述与目标
本文档定义了一款运行于 iOS/iPadOS 系统的远程桌面客户端应用（基于 RDP 协议），旨在提供高效、精确且流畅的 Windows 远程控制体验。支持触控手势、虚拟鼠标模式、外接物理外设以及画质/分辨率自适应调节。

---

## 2. 核心功能需求 (Functional Requirements)

### 2.1 远程画面显示与画质调节 (Display & Performance)

#### 2.1.1 分辨率与适配策略
* **匹配本地设备（Match Device Native）**：
  * 支持自动读取 iOS/iPadOS 物理分辨率（如 iPad Pro 2.7K）。
  * 自动触发 Windows DPI 缩放适配（提供 125%、150%、200% 等缩放预设建议）。
* **自定义分辨率（Custom Resolution）**：
  * 允许用户在连接设置中手动指定 1080p、1440p 或自定义像素尺寸，以平衡传输带宽。
* **画面填充/缩放（Fit to Screen）**：
  * 当远程 Windows 纵横比（如 16:9）与 iOS 屏幕（如 iPad 4:3）不一致时，提供“保持比例加黑边”与“无缝拉伸填充”两种模式切换。

#### 2.1.2 画质与网络自适应 (Adaptive Rendering)
* **画质优先模式（Optimize for Quality）**：
  * 强制开启 32 位真彩色及 ClearType 字体平滑，维持高图形细节（适用于 LAN 局域网环境）。
* **速度优先模式（Optimize for Speed）**：
  * 在低带宽/高延迟网络（4G/5G/弱网络）下，自动关闭 Windows 桌面壁纸、隐藏窗口拖动阴影与过渡动画，优先保证光标与点击响应速度。

#### 2.1.3 多屏与外接大屏支持
* **外接显示器扩展（External Display Extension）**：
  * 支持 iPad 通过 USB-C/HDMI 外接显示器时输出独占全屏远程画面，将 iPad 本身降级为独立触控板或保持运行其他 iOS 应用。
* **多监视器切换（Multi-Monitor Switching）**：
  * 针对多屏幕 Windows 主机，提供快捷切换标签页，支持在“显示器 1”、“显示器 2”之间快速跳转。

---

### 2.2 鼠标模式交互 (Mouse Pointer Interaction)

系统需提供**虚拟鼠标模式（Mouse Pointer Mode）**，将 iOS 屏幕转化为“笔记本触控板”机制。

#### 2.2.1 基础手势映射

| 手势动作 | 对应 Windows 鼠标功能 | 说明 / 触发条件 |
| :--- | :--- | :--- |
| **单指滑动** | 移动光标 (Cursor Movement) | 相对定位模式，无需直接点击目标图标 |
| **单指轻点 (Single Tap)** | 鼠标左键单击 (Left Click) | 光标所在位置触发点击 |
| **单指双击 (Double Tap)** | 鼠标左键双击 (Double Click) | 打开文件、文件夹或程序 |
| **双指同时轻点 (Two-Finger Tap)** | 鼠标右键单击 (Right Click) | 唤出右键快捷菜单 |
| **三指同时轻点 (Three-Finger Tap)**| 鼠标中键单击 (Middle Click) | 用于 CAD 平移或浏览器后台打开新标签页 |
| **单指长按拖拽 (Tap & Drag)** | 鼠标左键按住拖拽 | 单指快速双击，第二次按下不放并滑动（移动窗口/选中文本） |
| **双指上下/左右滑动** | 鼠标滚轮滑动 (Scroll Wheel) | 用于垂直或水平方向精确滚动页面/表格 |

#### 2.2.2 物理外设支持 (Physical Mouse & Trackpad)
* **原生按键映射**：接入蓝牙/USB 物理鼠标或 Apple Magic Trackpad 时，直接映射物理左键、右键及滚轮/中键点击。
* **光标锁定与捕获 (Pointer Capture)**：开启捕获模式后，光标移至 iOS 边缘不脱离窗口，支持 3D 建模及 FPS 游戏中的 360 度视角连续旋转。

---

### 2.3 画面与鼠标交互联动 (Interactive Feedback & Pan/Zoom)

#### 2.3.1 自动平移与视野控制 (Pan & Zoom)
* **边缘自动平移 (Auto-Panning)**：在画面放大状态或低分辨率屏幕上，当鼠标光标移动到 iOS 屏幕边缘时，远程画面自动沿该方向平移，保持光标在可视区域内。
* **双指独立操控**：
  * **双指拖拽**：在不改变 Windows 鼠标指针位置的情况下，单指控制光标，双指平移视口。
  * **双指捏合 (Pinch to Zoom)**：动态放大/缩小远程画面，提升微小控件的点击精度。

#### 2.3.2 状态提示与视觉反馈
* **光标形态同步**：实时接收并渲染 Windows 系统的光标样式变化（包含标准指针、文本 `I` 型光标、调整窗口大小双向箭头 `↔`、等待圆圈等）。
* **触控触觉反馈**：手势触发右键、中键或长按拖拽成功时，提供轻微的 iOS Haptic 振动与视觉波纹反馈。
* **光标自动隐藏**：全屏播放视频或演示无操作 3 秒后，自动隐藏鼠标光标。

---

### 2.4 工具栏与系统扩展 (Session Bar & Extensions)

#### 2.4.1 顶部控制栏 (Session Bar)
* **主页/多会话切换**：一键返回连接中心，支持无缝切换多个后台远程会话。
* **模式切换键**：一键在“直接触控模式 (Direct Touch)”与“模拟鼠标模式 (Mouse Pointer)”间快速切换。
* **软键盘与扩展按键行 (Virtual Keyboard & Modifier Keys)**：
  * 唤起键盘时，在顶部提供 Windows 专属修饰键：`Ctrl`、`Alt`、`Shift`、`Win`、`Tab`、`Esc` 及 `F1-F12`。
  * **修饰键锁定功能**：支持轻点锁定（如锁定 `Ctrl` 键高亮），配合鼠标模式轻点实现 `Ctrl + 鼠标左键`（多选文件）或 `Ctrl + 滚轮`（页面缩放）。

#### 2.4.2 系统重定向 (Redirection Features)
* **剪贴板双向同步 (Clipboard Sharing)**：支持 iOS 与 Windows 之间实时文本及图片的复制粘贴。
* **音频重定向 (Audio Redirection)**：将 Windows 播放的系统音频实时传输至 iOS 设备扬声器或蓝牙耳机。

---

## 3. 非功能性需求 (Non-Functional Requirements)

1. **延迟与流畅度**：在 100Mbps 局域网下，鼠标移动与画面渲染延时应控制在 **< 30ms**。
2. **兼容性**：支持 iOS 15.0 及以上版本；适配 iPadOS 独有的多任务与外接显示器特性。
3. **安全性**：支持 NLA（网络级别身份验证），数据传输默认启用 TLS/RDP 强加密。
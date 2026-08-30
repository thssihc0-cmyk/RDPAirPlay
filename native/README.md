# FreeRDP Native 桥接

`rdp_bridge.h` 是 Swift 与 FreeRDP 之间的 C API 边界。

## 文件

| 文件 | 说明 |
|------|------|
| `include/rdp_bridge.h` | 公开 C API |
| `include/rdp_bridge_internal.h` | 内部会话结构 |
| `include/rdp_bridge_freerdp.h` | FreeRDP 适配层声明 |
| `src/rdp_bridge.c` | API 实现、配置拷贝 |
| `src/rdp_bridge_freerdp.c` | FreeRDP 客户端逻辑（待补全） |

## 构建 FreeRDP

```bash
# 需先准备 iOS OpenSSL，或运行 FreeRDP 自带脚本后设置路径
export FREERDP_IOS_OPENSSL_PATH=/path/to/openssl-ios
chmod +x scripts/build_freerdp_ios.sh
./scripts/build_freerdp_ios.sh
```

构建成功后按 `native/dist/README.txt` 配置 Xcode 链接，并定义 `RDP_BRIDGE_HAS_FREERDP=1`。

## 音频通道（P0 Spike）

- **rdpsnd**：远程播放 → `on_audio_playback` → iOS 扬声器
- **audin**：iOS 麦克风 → `rdp_bridge_send_capture_audio` → 远程录音设备

验收：Windows 录音机电平随 iPhone 说话变化；微信通话双向可听。

## 当前状态

- 未链接 FreeRDP 时：`rdp_bridge_is_available()` 返回 `0`，App 使用 `StubRDPSession`
- 链接 FreeRDP 后：`NativeRDPSession` 接管；`rdp_bridge_freerdp.c` 需完成客户端线程与通道注册

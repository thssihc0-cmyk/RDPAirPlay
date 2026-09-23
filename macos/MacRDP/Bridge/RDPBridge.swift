import Foundation

/// Swift 封装 shared native C 桥接（FreeRDP 集成点）
enum RDPBridge {
    static var isAvailable: Bool {
        rdp_bridge_is_available() != 0
    }

    static func version() -> String {
        String(cString: rdp_bridge_version())
    }
}

/// FreeRDP 真连接会话（库未链接时工厂不会选用）
final class NativeRDPSession: RDPSessionHandling {
    weak var delegate: RDPSessionDelegate?

    private var handle: UnsafeMutableRawPointer?
    private let lock = NSLock()
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private let frameQueue = DispatchQueue(label: "com.macrdp.frame-decode", qos: .userInitiated)

    func connect(options: RDPConnectionOptions) async throws {
        guard RDPBridge.isAvailable else {
            throw RDPConnectionError.nativeBridgeUnavailable
        }

        let bridgeHandle = rdp_bridge_create()
        guard let bridgeHandle else {
            throw RDPConnectionError.disconnected("无法创建 RDP 会话")
        }
        handle = bridgeHandle

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            connectContinuation = continuation
            lock.unlock()

            let context = Unmanaged.passUnretained(self).toOpaque()
            var callbacks = rdp_bridge_callbacks(
                on_frame: macNativeFrameCallback,
                on_event: macNativeEventCallback,
                on_metrics: macNativeMetricsCallback,
                on_audio_playback: nil,
                on_cursor: nil,
                user_data: context
            )

            let result = options.hostname.withCString { host in
                options.username.withCString { user in
                    options.password.withCString { pass in
                        var config = rdp_bridge_config(
                            hostname: host,
                            port: Int32(options.port),
                            username: user,
                            password: pass,
                            width: Int32(options.width),
                            height: Int32(options.height),
                            enable_nla: options.enableNLA ? 1 : 0,
                            enable_speaker: options.enableSpeaker ? 1 : 0,
                            enable_microphone: 0,
                            optimize_for_speed: options.optimizeForSpeed ? 1 : 0
                        )
                        return rdp_bridge_connect(bridgeHandle, &config, &callbacks)
                    }
                }
            }

            if result != 0 {
                lock.lock()
                connectContinuation = nil
                lock.unlock()
                continuation.resume(throwing: RDPConnectionError.disconnected("启动连接失败 (\(result))"))
            }
        }
    }

    func disconnect() async {
        guard let bridgeHandle = handle else { return }
        handle = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                rdp_bridge_disconnect(bridgeHandle)
                rdp_bridge_destroy(bridgeHandle)
                continuation.resume()
            }
        }
    }

    func setResolution(width: Int, height: Int) async throws {
        guard let handle else { throw RDPConnectionError.disconnected("") }
        let code = rdp_bridge_set_resolution(handle, Int32(width), Int32(height))
        guard code == 0 else { throw RDPConnectionError.resolutionChangeFailed }
    }

    func sendMouse(_ event: RDPMouseEvent) {
        guard let handle else { return }
        let button = event.button == .left ? RDP_MOUSE_LEFT : RDP_MOUSE_RIGHT
        let action: Int32
        var deltaX: Int32 = 0
        var deltaY: Int32 = 0
        switch event.action {
        case .down: action = RDP_MOUSE_ACTION_DOWN
        case .up: action = RDP_MOUSE_ACTION_UP
        case .move: action = RDP_MOUSE_ACTION_MOVE
        case .scroll(let dx, let dy):
            action = RDP_MOUSE_ACTION_SCROLL
            deltaX = Int32(dx)
            deltaY = Int32(dy)
        }
        rdp_bridge_send_mouse(handle, Int32(event.x), Int32(event.y), button, action, deltaX, deltaY)
    }

    func sendKey(_ event: RDPKeyEvent) {
        guard let handle else { return }
        rdp_bridge_send_key(
            handle,
            event.keyCode,
            event.action == .down ? RDP_KEY_ACTION_DOWN : RDP_KEY_ACTION_UP,
            event.modifiers.rawValue
        )
    }

    func sendUnicodeText(_ text: String) {
        guard let handle else { return }
        text.withCString { rdp_bridge_send_text(handle, $0) }
    }

    fileprivate func resumeConnect(success: Bool, message: String?) {
        lock.lock()
        let cont = connectContinuation
        connectContinuation = nil
        lock.unlock()
        if success {
            cont?.resume()
            DispatchQueue.main.async { self.delegate?.sessionDidConnect() }
        } else {
            cont?.resume(throwing: RDPConnectionError.disconnected(message ?? "连接失败"))
        }
    }

    fileprivate func emitFrame(_ frame: rdp_bridge_frame) {
        guard let pixels = frame.pixels else { return }
        let width = Int(frame.width)
        let height = Int(frame.height)
        let stride = Int(frame.stride)
        let count = stride * height
        let data = Data(bytes: pixels, count: count)
        let timestamp = frame.timestamp
        frameQueue.async { [weak self] in
            guard let self else { return }
            guard let image = RDPFrameConverter.image(fromBGRA: data, width: width, height: height, stride: stride) else { return }
            let rdpFrame = RDPFrame(width: width, height: height, image: image, timestamp: timestamp)
            DispatchQueue.main.async {
                self.delegate?.sessionDidReceiveFrame(rdpFrame)
            }
        }
    }

    fileprivate func emitMetrics(rtt: Double, loss: Double, kbps: Int32) {
        DispatchQueue.main.async {
            self.delegate?.sessionDidUpdateMetrics(rttMs: rtt, lossPercent: loss, kbps: Int(kbps))
        }
    }

    fileprivate func emitDisconnect(message: String?) {
        DispatchQueue.main.async {
            self.delegate?.sessionDidDisconnect(error: message.map { .disconnected($0) })
        }
    }
}

private func macNativeFrameCallback(_ frame: UnsafePointer<rdp_bridge_frame>?, _ userData: UnsafeMutableRawPointer?) {
    guard let frame, let userData else { return }
    let session = Unmanaged<NativeRDPSession>.fromOpaque(userData).takeUnretainedValue()
    session.emitFrame(frame.pointee)
}

private func macNativeEventCallback(_ eventType: Int32, _ message: UnsafePointer<CChar>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let session = Unmanaged<NativeRDPSession>.fromOpaque(userData).takeUnretainedValue()
    let text = message.map { String(cString: $0) }
    switch eventType {
    case RDP_BRIDGE_EVENT_CONNECTED:
        session.resumeConnect(success: true, message: nil)
    case RDP_BRIDGE_EVENT_ERROR:
        session.resumeConnect(success: false, message: text)
        session.emitDisconnect(message: text)
    case RDP_BRIDGE_EVENT_DISCONNECTED:
        session.emitDisconnect(message: text)
    default:
        break
    }
}

private func macNativeMetricsCallback(_ rtt: Double, _ loss: Double, _ kbps: Int32, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let session = Unmanaged<NativeRDPSession>.fromOpaque(userData).takeUnretainedValue()
    session.emitMetrics(rtt: rtt, loss: loss, kbps: kbps)
}

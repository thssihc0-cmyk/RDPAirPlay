import Foundation

/// Swift 封装 native C 桥接（FreeRDP 集成点）
enum RDPBridge {
    static var isAvailable: Bool {
        rdp_bridge_is_available() != 0
    }

    static func version() -> String {
        String(cString: rdp_bridge_version())
    }
}

/// 使用 FreeRDP 的真实会话
final class NativeRDPSession: RDPSessionHandling {
    weak var delegate: RDPSessionDelegate?

    private var handle: UnsafeMutableRawPointer?
    private let lock = NSLock()
    private var connectContinuation: CheckedContinuation<Void, Error>?
    private let frameProcessingQueue = DispatchQueue(label: "com.rdpairplay.frame-decode", qos: .userInitiated)

    private var lastHost = ""
    private var lastPort = 3389

    func connect(options: RDPConnectionOptions) async throws {
        guard RDPBridge.isAvailable else {
            throw RDPConnectionError.nativeBridgeUnavailable
        }

        lastHost = options.hostname
        lastPort = options.port

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
                on_frame: nativeFrameCallback,
                on_event: nativeEventCallback,
                on_metrics: nativeMetricsCallback,
                on_audio_playback: nativeAudioPlaybackCallback,
                on_cursor: nativeCursorCallback,
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
                            enable_microphone: options.enableMicrophone ? 1 : 0,
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
                continuation.resume(throwing: mapStartError(result))
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
        let action = event.action == .down ? RDP_KEY_ACTION_DOWN : RDP_KEY_ACTION_UP
        rdp_bridge_send_key(handle, event.keyCode, action, event.modifiers.rawValue)
    }

    func sendUnicodeText(_ text: String) {
        guard let handle else { return }
        text.withCString { cString in
            rdp_bridge_send_text(handle, cString)
        }
    }

    fileprivate func handleFrame(_ frame: rdp_bridge_frame) {
        let width = Int(frame.width)
        let height = Int(frame.height)
        let stride = frame.stride > 0 ? Int(frame.stride) : width * 4
        guard width > 0, height > 0, let pixels = frame.pixels else { return }

        let dataSize = stride * height
        let pixelCopy = Data(bytes: pixels, count: dataSize)
        let timestamp = frame.timestamp

        frameProcessingQueue.async { [weak self] in
            let image = RDPFrameConverter.image(fromCopiedPixels: pixelCopy, width: width, height: height, stride: stride)
            let rdpFrame = RDPFrame(width: width, height: height, image: image, timestamp: timestamp)
            self?.delegate?.sessionDidReceiveFrame(rdpFrame)
        }
    }

    fileprivate func handleEvent(type: Int32, message: String) {
        let formatted = RDPErrorFormatter.friendlyMessage(for: message, host: lastHost, port: lastPort)
        switch type {
        case RDP_BRIDGE_EVENT_CONNECTED:
            lock.lock()
            connectContinuation?.resume()
            connectContinuation = nil
            lock.unlock()
            delegate?.sessionDidConnect()
        case RDP_BRIDGE_EVENT_DISCONNECTED:
            delegate?.sessionDidDisconnect(error: message.isEmpty ? nil : .disconnected(formatted))
        case RDP_BRIDGE_EVENT_ERROR:
            lock.lock()
            if let continuation = connectContinuation {
                continuation.resume(throwing: RDPConnectionError.disconnected(formatted))
                connectContinuation = nil
            }
            lock.unlock()
            delegate?.sessionDidDisconnect(error: .disconnected(formatted))
        default:
            break
        }
    }

    fileprivate func handleMetrics(rttMs: Double, lossPercent: Double, kbps: Int32) {
        delegate?.sessionDidUpdateMetrics(rttMs: rttMs, lossPercent: lossPercent, kbps: Int(kbps))
    }

    fileprivate func handleCursor(_ cursor: rdp_bridge_cursor) {
        let image = RDPFrameConverter.cursorImage(from: cursor)
        let rdpCursor = RDPCursor(
            image: image,
            hotspot: CGPoint(x: CGFloat(cursor.hotspot_x), y: CGFloat(cursor.hotspot_y)),
            position: CGPoint(x: CGFloat(cursor.x), y: CGFloat(cursor.y)),
            visible: cursor.visible != 0,
            updatesImageOnly: cursor.has_image != 0
        )
        delegate?.sessionDidReceiveCursor(rdpCursor)
    }

    private func mapStartError(_ code: Int32) -> RDPConnectionError {
        switch code {
        case -2: return .nativeBridgeUnavailable
        default: return .hostUnreachable
        }
    }
}

private func nativeFrameCallback(_ frame: UnsafePointer<rdp_bridge_frame>?, _ userData: UnsafeMutableRawPointer?) {
    guard let frame, let userData else { return }
    let session = Unmanaged<NativeRDPSession>.fromOpaque(userData).takeUnretainedValue()
    session.handleFrame(frame.pointee)
}

private func nativeEventCallback(_ eventType: Int32, _ message: UnsafePointer<CChar>?, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let session = Unmanaged<NativeRDPSession>.fromOpaque(userData).takeUnretainedValue()
    let text = message.map { String(cString: $0) } ?? ""
    session.handleEvent(type: eventType, message: text)
}

private func nativeMetricsCallback(_ rttMs: Double, _ lossPercent: Double, _ kbps: Int32, _ userData: UnsafeMutableRawPointer?) {
    guard let userData else { return }
    let session = Unmanaged<NativeRDPSession>.fromOpaque(userData).takeUnretainedValue()
    session.handleMetrics(rttMs: rttMs, lossPercent: lossPercent, kbps: kbps)
}

private func nativeAudioPlaybackCallback(_ chunk: UnsafePointer<rdp_bridge_audio_chunk>?, _ userData: UnsafeMutableRawPointer?) {
    _ = chunk
    _ = userData
}

private func nativeCursorCallback(_ cursor: UnsafePointer<rdp_bridge_cursor>?, _ userData: UnsafeMutableRawPointer?) {
    guard let cursor, let userData else { return }
    let session = Unmanaged<NativeRDPSession>.fromOpaque(userData).takeUnretainedValue()
    session.handleCursor(cursor.pointee)
}

import AppKit
import Combine
import Foundation

/// 会话中枢：画面、输入、色彩、弱网钩子（F-WN stubs）
@MainActor
final class RDPSessionController: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var displayImage: NSImage?
    @Published private(set) var statusLine: String = ""
    @Published var colorMode: ColorMode = .fullColor
    @Published var lockColorMode: Bool = false
    @Published private(set) var metricsText: String = ""
    @Published private(set) var weakNetTier: WeakNetAdaptiveController.Tier = .full

    private var session: RDPSessionHandling?
    private var host: HostProfile?
    private let adaptive = WeakNetAdaptiveController()
    private let inputPriority = InputPriorityScheduler()
    private let reconnect = AutoReconnectController()
    private let udpEval = UDPTransportEvaluator()
    private var frameSize = CGSize(width: 1280, height: 720)

    var bridgeSummary: String {
        RDPBridge.isAvailable
            ? "FreeRDP \(RDPBridge.version())"
            : "Stub（未链接 FreeRDP）"
    }

    func connect(host: HostProfile, password: String) async {
        self.host = host
        colorMode = host.colorMode
        lockColorMode = host.lockColorMode
        frameSize = CGSize(width: host.effectiveWidth, height: host.effectiveHeight)
        state = .connecting
        statusLine = "正在连接 \(host.hostname):\(host.port)…"

        let options = RDPConnectionOptions(
            hostname: host.hostname,
            port: host.port,
            username: host.username,
            password: password,
            width: host.effectiveWidth,
            height: host.effectiveHeight,
            enableNLA: ProductDefaults.nlaDefaultEnabled,
            enableSpeaker: host.enableSpeaker,
            optimizeForSpeed: true
        )

        let next = RDPSessionFactory.makeSession()
        next.delegate = self
        session = next

        // F-WN-04: 评估 UDP；不可用则 TCP + 更激进 A
        let transport = udpEval.evaluatePreferredTransport()
        statusLine = "传输：\(transport.rawValue.uppercased()) · \(bridgeSummary)"

        do {
            try await next.connect(options: options)
        } catch {
            state = .disconnected(message: error.localizedDescription)
            statusLine = error.localizedDescription
            session = nil
        }
    }

    func disconnect() async {
        reconnect.cancel()
        await session?.disconnect()
        session = nil
        state = .disconnected(message: nil)
        statusLine = "已断开"
    }

    func sendMouse(at point: CGPoint, button: RDPMouseEvent.Button, action: RDPMouseEvent.Action) {
        let event = RDPMouseEvent(x: Int(point.x), y: Int(point.y), button: button, action: action)
        inputPriority.enqueueMouse {
            self.session?.sendMouse(event)
        }
    }

    func sendKey(keyCode: UInt16, down: Bool, modifiers: RDPSessionModifiers) {
        let event = RDPKeyEvent(
            keyCode: keyCode,
            action: down ? .down : .up,
            modifiers: modifiers
        )
        inputPriority.enqueueKey {
            self.session?.sendKey(event)
        }
    }

    func sendText(_ text: String) {
        inputPriority.enqueueKey {
            self.session?.sendUnicodeText(text)
        }
    }

    private func applyColor(_ image: NSImage) -> NSImage {
        ColorModeProcessor.apply(colorMode, to: image)
    }
}

extension RDPSessionController: RDPSessionDelegate {
    nonisolated func sessionDidConnect() {
        Task { @MainActor in
            self.state = .connected
            self.statusLine = "已连接 · \(self.bridgeSummary)"
            self.reconnect.reset()
        }
    }

    nonisolated func sessionDidDisconnect(error: RDPConnectionError?) {
        Task { @MainActor in
            if let error {
                self.state = .disconnected(message: error.localizedDescription)
                self.statusLine = error.localizedDescription
                await self.maybeReconnect()
            } else {
                self.state = .disconnected(message: nil)
            }
        }
    }

    nonisolated func sessionDidReceiveFrame(_ frame: RDPFrame) {
        Task { @MainActor in
            self.frameSize = CGSize(width: frame.width, height: frame.height)
            if let image = frame.image {
                self.displayImage = self.applyColor(image)
            }
        }
    }

    nonisolated func sessionDidReceiveCursor(_ cursor: RDPCursor) {
        // First slice: rely on local pointer; remote cursor later.
        _ = cursor
    }

    nonisolated func sessionDidUpdateMetrics(rttMs: Double, lossPercent: Double, kbps: Int) {
        Task { @MainActor in
            self.metricsText = String(format: "RTT %.0f ms · loss %.1f%% · %d kbps", rttMs, lossPercent, kbps)
            if !self.lockColorMode {
                let decision = self.adaptive.evaluate(rttMs: rttMs, lossPercent: lossPercent, kbps: kbps)
                self.weakNetTier = decision.tier
                if let mode = decision.suggestedColorMode {
                    self.colorMode = mode
                }
            }
        }
    }

    private func maybeReconnect() async {
        guard let host else { return }
        guard let attempt = reconnect.nextAttempt() else { return }
        state = .reconnecting(attempt: attempt)
        statusLine = "重连中（第 \(attempt) 次）…"
        try? await Task.sleep(nanoseconds: UInt64(reconnect.delaySeconds(for: attempt) * 1_000_000_000))
        let password = KeychainService.loadPassword(account: host.keychainAccount) ?? ""
        await connect(host: host, password: password)
    }
}

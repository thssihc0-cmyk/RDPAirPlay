import AppKit
import Foundation

/// 无 FreeRDP 时的可运行占位：验证画面 + 键鼠路径
final class StubRDPSession: RDPSessionHandling {
    weak var delegate: RDPSessionDelegate?

    private var timer: Timer?
    private var width = 1280
    private var height = 720
    private var tick = 0
    private var lastMouse = CGPoint(x: 40, y: 40)
    private var lastKeyLabel = "—"

    func connect(options: RDPConnectionOptions) async throws {
        width = options.width
        height = options.height
        try await Task.sleep(nanoseconds: 400_000_000)

        if options.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RDPConnectionError.invalidConfiguration("主机地址不能为空")
        }
        if options.hostname == "fail.auth" {
            throw RDPConnectionError.authenticationFailed
        }
        if options.hostname == "fail.host" {
            throw RDPConnectionError.hostUnreachable
        }

        await MainActor.run {
            delegate?.sessionDidConnect()
            startFrameLoop()
        }
    }

    func disconnect() async {
        await MainActor.run {
            timer?.invalidate()
            timer = nil
            delegate?.sessionDidDisconnect(error: nil)
        }
    }

    func setResolution(width: Int, height: Int) async throws {
        self.width = width
        self.height = height
    }

    func sendMouse(_ event: RDPMouseEvent) {
        lastMouse = CGPoint(x: event.x, y: event.y)
    }

    func sendKey(_ event: RDPKeyEvent) {
        lastKeyLabel = "sc=\(event.keyCode) \(event.action == .down ? "↓" : "↑")"
    }

    func sendUnicodeText(_ text: String) {
        lastKeyLabel = "text=\(text.prefix(24))"
    }

    @MainActor
    private func startFrameLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            self.delegate?.sessionDidReceiveFrame(self.makePlaceholderFrame())
            self.delegate?.sessionDidUpdateMetrics(rttMs: 42, lossPercent: 0, kbps: 900)
        }
    }

    private func makePlaceholderFrame() -> RDPFrame {
        let size = NSSize(width: width, height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.12, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()

        let title = "macrdp — Stub 会话"
        let subtitle = "\(width)×\(height) · tick \(tick) · FreeRDP=\(RDPBridge.isAvailable ? "linked" : "stub")"
        let mouse = "mouse \(Int(lastMouse.x)),\(Int(lastMouse.y)) · \(lastKeyLabel)"
        let hint = "构建 macos FreeRDP 后显示真实远程桌面（F-DISP-01 / F-IN-01）"

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor(white: 0.85, alpha: 1),
        ]
        let hintAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15),
            .foregroundColor: NSColor(white: 0.6, alpha: 1),
        ]

        (title as NSString).draw(at: NSPoint(x: 36, y: height - 70), withAttributes: titleAttrs)
        (subtitle as NSString).draw(at: NSPoint(x: 36, y: height - 110), withAttributes: subAttrs)
        (mouse as NSString).draw(at: NSPoint(x: 36, y: height - 140), withAttributes: subAttrs)
        (hint as NSString).draw(at: NSPoint(x: 36, y: height - 180), withAttributes: hintAttrs)

        let pulse = CGFloat(tick % 30) / 30.0
        NSColor.systemTeal.withAlphaComponent(0.35).setFill()
        NSRect(x: 36, y: CGFloat(height - 280), width: 260 + pulse * 50, height: 52).fill()
        ("模拟远程窗口" as NSString).draw(at: NSPoint(x: 52, y: CGFloat(height - 265)), withAttributes: subAttrs)

        // 本地光标指示（输入路径可见）
        NSColor.systemYellow.setFill()
        NSRect(x: lastMouse.x - 4, y: CGFloat(height) - lastMouse.y - 4, width: 8, height: 8).fill()

        image.unlockFocus()
        return RDPFrame(width: width, height: height, image: image, timestamp: Date().timeIntervalSince1970)
    }
}

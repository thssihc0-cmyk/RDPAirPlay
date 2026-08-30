import CoreGraphics
import Foundation
import UIKit

/// 开发用 Stub：无 FreeRDP 时可运行 UI 与输入链路
final class StubRDPSession: RDPSessionHandling {
    weak var delegate: RDPSessionDelegate?

    private var timer: Timer?
    private var width = 1280
    private var height = 720
    private var tick = 0

    func connect(options: RDPConnectionOptions) async throws {
        width = options.width
        height = options.height

        // 模拟连接延迟
        try await Task.sleep(nanoseconds: 800_000_000)

        if options.hostname.isEmpty {
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
        // Stub: 输入已接收，后续由 FreeRDP 发送
    }

    func sendKey(_ event: RDPKeyEvent) {
        // Stub
    }

    func sendUnicodeText(_ text: String) {
        // Stub
    }

    @MainActor
    private func startFrameLoop() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.tick += 1
            let frame = self.makePlaceholderFrame()
            self.delegate?.sessionDidReceiveFrame(frame)
            self.delegate?.sessionDidUpdateMetrics(rttMs: 80, lossPercent: 0, kbps: 1800)
        }
    }

    private func makePlaceholderFrame() -> RDPFrame {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let image = renderer.image { ctx in
            UIColor(red: 0.08, green: 0.1, blue: 0.14, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let title = "RDPAirPlay — Stub 会话"
            let subtitle = "\(width) × \(height) · tick \(tick)"
            let hint = "构建 native/FreeRDP 后将显示真实远程桌面"

            let attrsTitle: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 36, weight: .bold),
                .foregroundColor: UIColor.white,
            ]
            let attrsSub: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor(white: 0.85, alpha: 1),
            ]
            let attrsHint: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18),
                .foregroundColor: UIColor(white: 0.65, alpha: 1),
            ]

            title.draw(at: CGPoint(x: 40, y: 40), withAttributes: attrsTitle)
            subtitle.draw(at: CGPoint(x: 40, y: 100), withAttributes: attrsSub)
            hint.draw(at: CGPoint(x: 40, y: 150), withAttributes: attrsHint)

            UIColor.systemBlue.withAlphaComponent(0.35).setFill()
            let pulse = CGFloat((tick % 24)) / 24.0
            ctx.fill(CGRect(x: 40, y: 220, width: 280 + pulse * 40, height: 56))
            "模拟远程窗口".draw(in: CGRect(x: 56, y: 232, width: 260, height: 32), withAttributes: attrsSub)
        }

        return RDPFrame(
            width: width,
            height: height,
            image: image,
            timestamp: Date().timeIntervalSince1970
        )
    }
}

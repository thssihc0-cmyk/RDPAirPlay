import Foundation
import Combine

/// F-NET-01: 弱网质量监测（占位实现，后续接入真实 RTT/丢包）
@MainActor
final class NetworkQualityMonitor: ObservableObject {
    enum BandwidthTier: String {
        case high = "高"
        case medium = "中"
        case low = "低"
    }

    @Published private(set) var tier: BandwidthTier = .high
    @Published private(set) var estimatedKbps: Int = 2000

    private var timer: Timer?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// 由 RDP 层上报真实指标时调用
    func report(rttMs: Double, lossPercent: Double, kbps: Int) {
        estimatedKbps = kbps
        if lossPercent > 15 || rttMs > 350 || kbps < 400 {
            tier = .low
        } else if lossPercent > 5 || rttMs > 180 || kbps < 900 {
            tier = .medium
        } else {
            tier = .high
        }
    }

    func suggestedColorMode(current: ColorMode, locked: Bool) -> ColorMode {
        guard !locked else { return current }
        switch tier {
        case .high: return .fullColor
        case .medium: return current == .monochrome ? .monochrome : .grayscale
        case .low: return .monochrome
        }
    }

    private func tick() {
        // Stub: 等待 native 层回调；开发阶段保持高档
    }
}

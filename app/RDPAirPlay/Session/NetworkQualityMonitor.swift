import Foundation
import Combine

/// F-NET-01: 弱网质量监测（帧带宽估算 + 路径类型）
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

    /// 连续低档位采样次数（用于触发重连以应用 RDP 性能标志）
    private(set) var consecutiveLowSamples = 0

    var shouldEnableSpeedOptimization: Bool {
        tier == .low
    }

    func start() {
        stop()
        consecutiveLowSamples = 0
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        consecutiveLowSamples = 0
    }

    /// 由帧估算或 RDP 层上报的真实指标
    func report(rttMs: Double, lossPercent: Double, kbps: Int) {
        estimatedKbps = kbps
        let previousTier = tier
        if lossPercent > 15 || rttMs > 350 || kbps < 400 {
            tier = .low
        } else if lossPercent > 5 || rttMs > 180 || kbps < 900 {
            tier = .medium
        } else {
            tier = .high
        }
        if tier == .low {
            consecutiveLowSamples += 1
        } else if previousTier == .low {
            consecutiveLowSamples = 0
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
        // 帧估算为主；此处保留定时器以便后续接入 native RTT/丢包
    }
}

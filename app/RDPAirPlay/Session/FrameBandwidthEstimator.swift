import Foundation

/// 根据帧到达间隔与像素量估算带宽与交互延迟，供弱网自适应使用
struct FrameBandwidthEstimator {
    private var byteAccumulator = 0
    private var lastReport = Date()
    private var lastFrame = Date()
    private var intervalEMA: Double = 0

    mutating func recordFrame(width: Int, height: Int) -> (kbps: Int, rttMs: Double)? {
        let now = Date()
        let intervalMs = now.timeIntervalSince(lastFrame) * 1000
        lastFrame = now
        if intervalMs > 0 {
            intervalEMA = intervalEMA == 0 ? intervalMs : intervalEMA * 0.75 + intervalMs * 0.25
        }

        byteAccumulator += max(width, 0) * max(height, 0) * 4
        guard now.timeIntervalSince(lastReport) >= 3 else { return nil }

        let seconds = now.timeIntervalSince(lastReport)
        let kbps = Int(Double(byteAccumulator * 8) / seconds / 1000)
        byteAccumulator = 0
        lastReport = now
        return (max(kbps, 0), max(intervalEMA, 0))
    }

    mutating func reset() {
        byteAccumulator = 0
        lastReport = Date()
        lastFrame = Date()
        intervalEMA = 0
    }
}

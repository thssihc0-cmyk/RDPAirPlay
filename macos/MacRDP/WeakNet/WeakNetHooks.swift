import Foundation

/// F-WN-01: 自适应画质（帧率/分辨率/压缩/色深）— 首切片为策略钩子
struct WeakNetAdaptiveController {
    enum Tier: String, CaseIterable {
        case full
        case balanced
        case aggressive

        var displayName: String {
            switch self {
            case .full: return "全画质"
            case .balanced: return "均衡"
            case .aggressive: return "激进降档"
            }
        }
    }

    struct Decision {
        let tier: Tier
        let suggestedColorMode: ColorMode?
        let targetFPS: Int
    }

    func evaluate(rttMs: Double, lossPercent: Double, kbps: Int) -> Decision {
        if rttMs > 500 || lossPercent > 5 || kbps < 400 {
            return Decision(tier: .aggressive, suggestedColorMode: .monochrome, targetFPS: 8)
        }
        if rttMs > 200 || lossPercent > 1 || kbps < 1200 {
            return Decision(tier: .balanced, suggestedColorMode: .grayscale, targetFPS: 15)
        }
        return Decision(tier: .full, suggestedColorMode: .fullColor, targetFPS: 30)
    }
}

/// F-WN-02: 输入优先 — 键鼠优先于刷新调度
final class InputPriorityScheduler {
    private let queue = DispatchQueue(label: "com.macrdp.input-priority")

    func enqueueMouse(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    func enqueueKey(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }
}

/// F-WN-03: 自动重连 + 可见状态
final class AutoReconnectController {
    private(set) var attempts = 0
    var maxAttempts = 5

    func reset() { attempts = 0 }
    func cancel() { attempts = maxAttempts }

    func nextAttempt() -> Int? {
        guard attempts < maxAttempts else { return nil }
        attempts += 1
        return attempts
    }

    func delaySeconds(for attempt: Int) -> Double {
        min(30, pow(2.0, Double(attempt - 1)))
    }
}

/// F-WN-04: UDP 评估；失败回退 TCP
enum PreferredTransport: String {
    case tcp
    case udp
}

struct UDPTransportEvaluator {
    /// 首切片：探测钩子；真实协商待 FreeRDP UDP 编译选项
    func evaluatePreferredTransport(udpCapabilityKnown: Bool = false, udpLikelyBlocked: Bool = true) -> PreferredTransport {
        if udpCapabilityKnown && !udpLikelyBlocked {
            return .udp
        }
        return .tcp
    }
}

/// F-WN-05: 会话恢复深度钩子（尽量；否则重连新会话）
enum SessionResumePolicy {
    case bestEffortResume
    case freshLoginAcceptable
}

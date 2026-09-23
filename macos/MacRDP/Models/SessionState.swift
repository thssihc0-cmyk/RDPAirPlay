import Foundation

/// F-CONN-03: 连接中 / 已连接 / 重连中 / 已断开
enum SessionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case disconnected(message: String?)

    var label: String {
        switch self {
        case .idle: return "未连接"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .reconnecting(let n): return "重连中（第 \(n) 次）…"
        case .disconnected(let msg):
            if let msg, !msg.isEmpty { return "已断开：\(msg)" }
            return "已断开"
        }
    }
}

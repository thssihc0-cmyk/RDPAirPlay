import Foundation

/// F-CONN-04: 连接状态
enum SessionState: Equatable {
    case idle
    case connecting
    case connected
    case reconnecting
    case disconnected(reason: String?)

    var displayName: String {
        switch self {
        case .idle: return "未连接"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .reconnecting: return "重连中…"
        case .disconnected: return "已断开"
        }
    }

    var isActive: Bool {
        switch self {
        case .connecting, .connected, .reconnecting:
            return true
        default:
            return false
        }
    }
}

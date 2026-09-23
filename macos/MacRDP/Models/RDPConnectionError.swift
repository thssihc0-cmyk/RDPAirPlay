import Foundation

enum RDPConnectionError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case authenticationFailed
    case hostUnreachable
    case nativeBridgeUnavailable
    case disconnected(String)
    case resolutionChangeFailed

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason): return "配置无效：\(reason)"
        case .authenticationFailed: return "认证失败（请检查用户名/密码/NLA）"
        case .hostUnreachable: return "无法到达主机"
        case .nativeBridgeUnavailable: return "FreeRDP 未链接，当前为 Stub 会话"
        case .disconnected(let reason): return reason.isEmpty ? "连接已断开" : reason
        case .resolutionChangeFailed: return "分辨率修改失败"
        }
    }
}

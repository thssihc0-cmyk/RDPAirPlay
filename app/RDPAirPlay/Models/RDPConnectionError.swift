import Foundation

/// F-CONN-06: 可读连接错误
enum RDPConnectionError: LocalizedError, Equatable {
    case hostUnreachable
    case authenticationFailed
    case tlsOrNLAFailed
    case timeout
    case invalidConfiguration(String)
    case nativeBridgeUnavailable
    case resolutionChangeFailed
    case transportFailed(host: String, port: Int)
    case disconnected(String)

    var errorDescription: String? {
        switch self {
        case .hostUnreachable:
            return "无法连接到主机，请检查地址、端口与网络。"
        case .authenticationFailed:
            return "用户名或密码错误。"
        case .tlsOrNLAFailed:
            return "安全协商失败（TLS/NLA），请确认 Windows 远程桌面设置。"
        case .timeout:
            return "连接超时，请稍后重试。"
        case .invalidConfiguration(let detail):
            return "配置无效：\(detail)"
        case .nativeBridgeUnavailable:
            return "RDP 引擎未就绪。请先构建 native/FreeRDP 桥接层。"
        case .resolutionChangeFailed:
            return "修改分辨率失败，将尝试重新连接。"
        case .disconnected(let reason):
            return reason.isEmpty ? "连接已断开。" : reason
        case .transportFailed(let host, let port):
            return RDPErrorFormatter.friendlyMessage(
                for: "ERRCONNECT_CONNECT_TRANSPORT_FAILED",
                host: host,
                port: port
            )
        }
    }
}

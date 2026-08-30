import Foundation

enum RDPErrorFormatter {
    static func friendlyMessage(for raw: String, host: String, port: Int) -> String {
        let engine = RDPBridge.version()
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "[\(engine)] \(host):\(port) 连接失败（无详细信息）"
        }
        return "[\(engine)] \(raw)"
    }
}

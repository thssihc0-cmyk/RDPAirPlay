import Foundation
import Network

/// 检测当前网络路径（蜂窝 / 低数据模式）以决定连接时是否启用 RDP 速度优先模式
@MainActor
final class NetworkPathObserver: ObservableObject {
    static let shared = NetworkPathObserver()

    @Published private(set) var prefersSpeedOptimization = false
    @Published private(set) var usesCellular = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rdpairplay.network-path")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular)
            let constrained = path.isConstrained || path.isExpensive
            Task { @MainActor in
                self?.usesCellular = cellular
                self?.prefersSpeedOptimization = cellular || constrained
            }
        }
        monitor.start(queue: queue)
    }
}

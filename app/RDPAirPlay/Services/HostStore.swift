import Foundation
import Combine

/// F-CONN-01: 主机列表持久化（不含密码）
@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [HostProfile] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("RDPAirPlay", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("hosts.json")
        load()
    }

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([HostProfile].self, from: data) else {
            hosts = []
            return
        }
        hosts = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func save() {
        guard let data = try? encoder.encode(hosts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func upsert(_ host: HostProfile, password: String?) throws {
        var updated = host
        updated.updatedAt = Date()
        if let index = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[index] = updated
        } else {
            hosts.insert(updated, at: 0)
        }
        if let password, !password.isEmpty {
            try KeychainService.savePassword(password, account: updated.keychainAccount)
        }
        save()
    }

    func delete(_ host: HostProfile) {
        KeychainService.deletePassword(account: host.keychainAccount)
        hosts.removeAll { $0.id == host.id }
        save()
    }

    func password(for host: HostProfile) throws -> String? {
        try KeychainService.loadPassword(account: host.keychainAccount)
    }
}

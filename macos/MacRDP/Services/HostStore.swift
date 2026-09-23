import Foundation
import Combine

@MainActor
final class HostStore: ObservableObject {
    @Published private(set) var hosts: [HostProfile] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("MacRDP", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("hosts.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    func upsert(_ host: HostProfile, password: String?) throws {
        var next = host
        next.updatedAt = Date()
        if let idx = hosts.firstIndex(where: { $0.id == host.id }) {
            hosts[idx] = next
        } else {
            hosts.insert(next, at: 0)
        }
        if let password {
            try KeychainService.savePassword(password, account: next.keychainAccount)
        }
        save()
    }

    func delete(_ host: HostProfile) {
        hosts.removeAll { $0.id == host.id }
        KeychainService.deletePassword(account: host.keychainAccount)
        save()
    }

    func password(for host: HostProfile) -> String? {
        KeychainService.loadPassword(account: host.keychainAccount)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([HostProfile].self, from: data) else {
            hosts = []
            return
        }
        hosts = decoded
    }

    private func save() {
        guard let data = try? encoder.encode(hosts) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

import Foundation

/// F-CONN-01: 主机配置（密码仅 Keychain，不落此模型）
struct HostProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var displayName: String
    var hostname: String
    var port: Int
    var username: String
    var resolution: ResolutionPreset
    var customWidth: Int?
    var customHeight: Int?
    var colorMode: ColorMode
    var lockColorMode: Bool
    var enableSpeaker: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        displayName: String = "",
        hostname: String = "",
        port: Int = 3389,
        username: String = "",
        resolution: ResolutionPreset = .presets[0],
        customWidth: Int? = nil,
        customHeight: Int? = nil,
        colorMode: ColorMode = .fullColor,
        lockColorMode: Bool = false,
        enableSpeaker: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.displayName = displayName
        self.hostname = hostname
        self.port = port
        self.username = username
        self.resolution = resolution
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.colorMode = colorMode
        self.lockColorMode = lockColorMode
        self.enableSpeaker = enableSpeaker
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var effectiveWidth: Int { customWidth ?? resolution.width }
    var effectiveHeight: Int { customHeight ?? resolution.height }

    var keychainAccount: String { "host.\(id.uuidString).password" }

    var title: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? hostname : name
    }
}

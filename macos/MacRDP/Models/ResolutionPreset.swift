import Foundation

struct ResolutionPreset: Codable, Equatable, Identifiable, Hashable {
    var id: String { "\(width)x\(height)" }
    let name: String
    let width: Int
    let height: Int

    static let presets: [ResolutionPreset] = [
        ResolutionPreset(name: "1280×720", width: 1280, height: 720),
        ResolutionPreset(name: "1920×1080", width: 1920, height: 1080),
        ResolutionPreset(name: "1600×900", width: 1600, height: 900),
        ResolutionPreset(name: "1024×768", width: 1024, height: 768),
    ]
}

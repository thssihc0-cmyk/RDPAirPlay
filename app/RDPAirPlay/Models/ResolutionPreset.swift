import Foundation
import CoreGraphics

/// F-DISP-01: 连接前分辨率预设
struct ResolutionPreset: Codable, Hashable, Identifiable {
    let width: Int
    let height: Int
    let label: String

    var id: String { "\(width)x\(height)" }

    var size: CGSize {
        CGSize(width: width, height: height)
    }

    static let presets: [ResolutionPreset] = [
        ResolutionPreset(width: 1280, height: 720, label: "720p"),
        ResolutionPreset(width: 1920, height: 1080, label: "1080p"),
        ResolutionPreset(width: 2560, height: 1440, label: "1440p"),
    ]

    static let minWidth = 640
    static let minHeight = 480
    static let maxWidth = 3840
    static let maxHeight = 2160

    static func validate(width: Int, height: Int) -> Bool {
        width >= minWidth && width <= maxWidth &&
        height >= minHeight && height <= maxHeight
    }
}

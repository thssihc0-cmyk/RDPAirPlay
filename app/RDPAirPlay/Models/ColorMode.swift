import Foundation

/// F-NET-02: 全彩 / 灰度 / 黑白
enum ColorMode: String, Codable, CaseIterable, Identifiable {
    case fullColor
    case grayscale
    case monochrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullColor: return "全彩"
        case .grayscale: return "灰度"
        case .monochrome: return "黑白"
        }
    }

    /// 弱网自适应时的降档顺序
    static let degradationOrder: [ColorMode] = [.fullColor, .grayscale, .monochrome]
}

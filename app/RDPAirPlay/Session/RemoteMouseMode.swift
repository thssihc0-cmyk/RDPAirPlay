import Foundation

/// 与 Microsoft Remote Desktop / Windows App 一致的两档鼠标模式
enum RemoteMouseMode: String, CaseIterable, Identifiable {
    case directTouch
    case mousePointer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .directTouch: return "直接触控"
        case .mousePointer: return "鼠标指针"
        }
    }

    var iconName: String {
        switch self {
        case .directTouch: return "hand.tap"
        case .mousePointer: return "cursorarrow"
        }
    }

    mutating func toggle() {
        self = self == .directTouch ? .mousePointer : .directTouch
    }
}

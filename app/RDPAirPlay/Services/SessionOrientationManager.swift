import SwiftUI
import UIKit

/// 会话内横竖屏控制
@MainActor
final class SessionOrientationManager: ObservableObject {
    static let shared = SessionOrientationManager()

    enum Preference: String, CaseIterable, Identifiable {
        case auto
        case portrait
        case landscape

        var id: String { rawValue }

        var toolbarLabel: String {
            switch self {
            case .auto: return "自动"
            case .portrait: return "竖屏"
            case .landscape: return "横屏"
            }
        }

        var iconName: String {
            switch self {
            case .auto: return "arrow.triangle.2.circlepath"
            case .portrait: return "iphone"
            case .landscape: return "iphone.landscape"
            }
        }
    }

    @Published private(set) var preference: Preference = .auto

    var mask: UIInterfaceOrientationMask {
        switch preference {
        case .auto: return .allButUpsideDown
        case .portrait: return .portrait
        case .landscape: return .landscape
        }
    }

    func cyclePreference() {
        switch preference {
        case .auto: preference = .landscape
        case .landscape: preference = .portrait
        case .portrait: preference = .auto
        }
        apply()
    }

    func reset() {
        preference = .auto
        apply()
    }

    func apply() {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else {
            return
        }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

import UIKit

extension Notification.Name {
    static let externalDisplaySceneDidConnect = Notification.Name("RDPAirPlay.externalDisplaySceneDidConnect")
}

/// 外接屏 Scene：必须在 willConnect 内立刻挂上 UIWindow，否则系统只会镜像、不给扩展 Scene。
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        guard Self.isExternalRole(session.role) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.backgroundColor = .black
        window.rootViewController = ExternalDisplayManager.makePlaceholderController()
        window.isHidden = false
        self.window = window

        Task { @MainActor in
            ExternalDisplayManager.shared()?.integrateExternalScene(windowScene, window: window)
        }
        NotificationCenter.default.post(name: .externalDisplaySceneDidConnect, object: scene)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene,
              Self.isExternalRole(windowScene.session.role) else { return }
        Task { @MainActor in
            if let window {
                ExternalDisplayManager.shared()?.integrateExternalScene(windowScene, window: window)
            }
        }
        NotificationCenter.default.post(name: .externalDisplaySceneDidConnect, object: scene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene,
              Self.isExternalRole(windowScene.session.role) else { return }
        Task { @MainActor in
            ExternalDisplayManager.shared()?.externalSceneDidDisconnect(windowScene)
        }
        window = nil
    }

    private static func isExternalRole(_ role: UISceneSession.Role) -> Bool {
        if role == .windowExternalDisplayNonInteractive { return true }
        return role.rawValue.contains("ExternalDisplay")
    }
}

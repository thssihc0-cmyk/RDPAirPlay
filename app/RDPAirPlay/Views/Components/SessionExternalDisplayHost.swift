import SwiftUI
import UIKit

/// 会话期间保持外接 Scene 激活并周期性刷新检测
struct SessionExternalDisplayHost: UIViewControllerRepresentable {
    @EnvironmentObject private var externalDisplay: ExternalDisplayManager

    func makeUIViewController(context: Context) -> SessionExternalDisplayViewController {
        let controller = SessionExternalDisplayViewController()
        controller.manager = externalDisplay
        return controller
    }

    func updateUIViewController(_ uiViewController: SessionExternalDisplayViewController, context: Context) {
        uiViewController.manager = externalDisplay
    }
}

final class SessionExternalDisplayViewController: UIViewController {
    weak var manager: ExternalDisplayManager?

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        manager?.refreshConnection()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if #available(iOS 17.0, *) {
            if traitCollection.sceneCaptureState != previousTraitCollection?.sceneCaptureState {
                manager?.refreshConnection()
            }
        } else if UIScreen.main.isCaptured {
            manager?.refreshConnection()
        }
    }
}

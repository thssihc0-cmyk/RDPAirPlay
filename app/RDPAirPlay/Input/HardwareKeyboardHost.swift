import GameController
import SwiftUI
import UIKit

/// 捕获蓝牙 / 妙控等外接键盘，映射为 RDP 扫描码
struct HardwareKeyboardHost: UIViewRepresentable {
    @ObservedObject var controller: RDPSessionController
    @Binding var softwareKeyboardVisible: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> HardwareKeyboardCaptureView {
        let view = HardwareKeyboardCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.captureView = view
        context.coordinator.refreshCaptureState(softwareKeyboardVisible: softwareKeyboardVisible)
        return view
    }

    func updateUIView(_ uiView: HardwareKeyboardCaptureView, context: Context) {
        context.coordinator.controller = controller
        context.coordinator.refreshCaptureState(softwareKeyboardVisible: softwareKeyboardVisible)
    }

    final class Coordinator {
        var controller: RDPSessionController
        weak var captureView: HardwareKeyboardCaptureView?
        private var softwareKeyboardVisible = false
        private var observers: [NSObjectProtocol] = []

        init(controller: RDPSessionController) {
            self.controller = controller
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.refreshCaptureState(softwareKeyboardVisible: self.softwareKeyboardVisible)
            })
            observers.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                self?.captureView?.resignFirstResponder()
            })
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        func refreshCaptureState(softwareKeyboardVisible: Bool) {
            self.softwareKeyboardVisible = softwareKeyboardVisible
            guard let captureView else { return }
            let hardwareConnected = GCKeyboard.coalesced != nil
            captureView.isHardwareCaptureEnabled = hardwareConnected && !softwareKeyboardVisible
            if captureView.isHardwareCaptureEnabled {
                captureView.becomeFirstResponder()
            } else {
                captureView.resignFirstResponder()
            }
        }

        func handlePresses(_ presses: Set<UIPress>, ended: Bool) {
            let action: RDPKeyEvent.Action = ended ? .up : .down
            var events: [(UInt16, RDPKeyEvent.Action)] = []
            for press in presses {
                guard let key = press.key,
                      let code = HardwareKeyboardMapper.rdpScanCode(for: key) else { continue }
                events.append((code, action))
            }
            guard !events.isEmpty else { return }
            Task { @MainActor in
                for (code, action) in events {
                    controller.sendHardwareKey(code, action: action)
                }
            }
        }
    }
}

final class HardwareKeyboardCaptureView: UIView {
    weak var coordinator: HardwareKeyboardHost.Coordinator?
    var isHardwareCaptureEnabled = false

    override var canBecomeFirstResponder: Bool { isHardwareCaptureEnabled }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isHardwareCaptureEnabled else {
            super.pressesBegan(presses, with: event)
            return
        }
        coordinator?.handlePresses(presses, ended: false)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isHardwareCaptureEnabled else {
            super.pressesEnded(presses, with: event)
            return
        }
        coordinator?.handlePresses(presses, ended: true)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard isHardwareCaptureEnabled else {
            super.pressesCancelled(presses, with: event)
            return
        }
        coordinator?.handlePresses(presses, ended: true)
    }
}

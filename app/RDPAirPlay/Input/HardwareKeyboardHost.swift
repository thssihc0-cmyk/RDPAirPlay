import GameController
import SwiftUI
import UIKit

/// 捕获蓝牙 / 妙控等外接键盘，映射为 RDP 扫描码
struct HardwareKeyboardHost: UIViewRepresentable {
    var softwareKeyboardVisible: Bool
    var onHardwareKey: (_ code: UInt16, _ action: RDPKeyEvent.Action) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onHardwareKey: onHardwareKey)
    }

    func makeUIView(context: Context) -> HardwareKeyboardCaptureView {
        let view = HardwareKeyboardCaptureView()
        view.coordinator = context.coordinator
        context.coordinator.captureView = view
        context.coordinator.refreshCaptureState(softwareKeyboardVisible: softwareKeyboardVisible)
        return view
    }

    func updateUIView(_ uiView: HardwareKeyboardCaptureView, context: Context) {
        context.coordinator.onHardwareKey = onHardwareKey
        context.coordinator.refreshCaptureState(softwareKeyboardVisible: softwareKeyboardVisible)
    }

    final class Coordinator {
        var onHardwareKey: (_ code: UInt16, _ action: RDPKeyEvent.Action) -> Void
        weak var captureView: HardwareKeyboardCaptureView?
        private var softwareKeyboardVisible = false
        private var appliedCaptureEnabled: Bool?
        private var observers: [NSObjectProtocol] = []

        init(onHardwareKey: @escaping (_ code: UInt16, _ action: RDPKeyEvent.Action) -> Void) {
            self.onHardwareKey = onHardwareKey
            let center = NotificationCenter.default
            observers.append(center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.refreshCaptureState(softwareKeyboardVisible: self.softwareKeyboardVisible)
            })
            observers.append(center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                self?.appliedCaptureEnabled = false
                self?.captureView?.isHardwareCaptureEnabled = false
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
            let enabled = hardwareConnected && !softwareKeyboardVisible
            if appliedCaptureEnabled == enabled {
                return
            }
            appliedCaptureEnabled = enabled
            captureView.isHardwareCaptureEnabled = enabled
            if enabled {
                captureView.becomeFirstResponder()
            } else if captureView.isFirstResponder {
                captureView.resignFirstResponder()
            }
        }

        func handlePresses(_ presses: Set<UIPress>, ended: Bool) {
            let action: RDPKeyEvent.Action = ended ? .up : .down
            for press in presses {
                guard let key = press.key,
                      let code = HardwareKeyboardMapper.rdpScanCode(for: key) else { continue }
                onHardwareKey(code, action)
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

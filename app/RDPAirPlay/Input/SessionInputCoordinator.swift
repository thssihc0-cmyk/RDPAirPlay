import Foundation
import SwiftUI

/// 稳定的键盘/输入回调入口，避免 SwiftUI 每帧重建闭包导致 IME 宿主被反复 update
@MainActor
final class SessionInputCoordinator: ObservableObject {
    private weak var controller: RDPSessionController?

    func attach(to controller: RDPSessionController) {
        self.controller = controller
    }

    func sendText(_ text: String) {
        controller?.sendText(text)
    }

    func sendDelete() {
        controller?.sendKeyTap(RDPScanCode.backspace)
    }

    func sendReturn() {
        controller?.sendKeyTap(RDPScanCode.enter)
    }

    func sendHardwareKey(_ code: UInt16, action: RDPKeyEvent.Action) {
        controller?.sendHardwareKey(code, action: action)
    }
}

/// 与帧刷新解耦的输入宿主：仅随键盘开关状态更新
struct SessionInputHosts: View, Equatable {
    @ObservedObject var coordinator: SessionInputCoordinator
    @Binding var showKeyboard: Bool
    @Binding var useSystemKeyboard: Bool

    static func == (lhs: SessionInputHosts, rhs: SessionInputHosts) -> Bool {
        lhs.showKeyboard == rhs.showKeyboard && lhs.useSystemKeyboard == rhs.useSystemKeyboard
    }

    var body: some View {
        Group {
            RemoteKeyboardHost(
                isActive: Binding(
                    get: { showKeyboard && useSystemKeyboard },
                    set: { active in
                        if !active {
                            useSystemKeyboard = false
                        }
                    }
                ),
                onInsert: { coordinator.sendText($0) },
                onDelete: { coordinator.sendDelete() },
                onReturn: { coordinator.sendReturn() }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)

            HardwareKeyboardHost(
                softwareKeyboardVisible: showKeyboard,
                onHardwareKey: { code, action in
                    coordinator.sendHardwareKey(code, action: action)
                }
            )
            .frame(width: 1, height: 1)
            .opacity(0.01)
            .allowsHitTesting(false)
        }
    }
}

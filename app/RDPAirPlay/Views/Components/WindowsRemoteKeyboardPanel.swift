import SwiftUI

/// Microsoft Remote Desktop 风格完整软键盘：辅助键区 + 修饰键 + QWERTY
struct WindowsRemoteKeyboardPanel: View {
    @ObservedObject var controller: RDPSessionController
    var onRequestSystemKeyboard: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            WindowsAuxiliaryKeyboardView(controller: controller)
            Divider().overlay(Color.white.opacity(0.12))
            ModifierToggleBar(controller: controller)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(white: 0.1))
            OnScreenKeyboardView(controller: controller, onRequestSystemKeyboard: onRequestSystemKeyboard)
        }
    }
}

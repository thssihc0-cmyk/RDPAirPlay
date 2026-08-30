import SwiftUI

/// Microsoft Remote Desktop 风格辅助键盘（Fn / 123 / 方向键 三页）
struct WindowsAuxiliaryKeyboardView: View {
    @ObservedObject var controller: RDPSessionController
    @State private var page: Page = .function

    private enum Page {
        case function
        case numpad
        case arrows
    }

    var body: some View {
        Group {
            switch page {
            case .function: functionPage
            case .numpad: numpadPage
            case .arrows: arrowsPage
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
        .background(Color(white: 0.12))
    }

    private var functionPage: some View {
        VStack(spacing: 4) {
            row(
                key("F1", RDPScanCode.f1), key("F2", RDPScanCode.f2), key("F3", RDPScanCode.f3),
                key("F4", RDPScanCode.f4), key("F5", RDPScanCode.f5), key("F6", RDPScanCode.f6)
            )
            row(
                key("F7", RDPScanCode.f7), key("F8", RDPScanCode.f8), key("F9", RDPScanCode.f9),
                key("F10", RDPScanCode.f10), key("F11", RDPScanCode.f11), key("F12", RDPScanCode.f12)
            )
            row(
                nav("⌨") { page = .arrows }, key("Tab", RDPScanCode.tab), key("Ins", RDPScanCode.insert),
                key("Home", RDPScanCode.home), key("PgUp", RDPScanCode.pageUp), modifier("Win", .win)
            )
            row(
                nav("123") { page = .numpad }, key("PrtSc", RDPScanCode.printScreen), key("Del", RDPScanCode.delete),
                key("End", RDPScanCode.end), key("PgDn", RDPScanCode.pageDown), key("Menu", RDPScanCode.apps)
            )
        }
    }

    private var numpadPage: some View {
        VStack(spacing: 4) {
            row(
                unicode("("), unicode(")"), key("7", RDPScanCode.numpad7), key("8", RDPScanCode.numpad8),
                key("9", RDPScanCode.numpad9), key("-", RDPScanCode.numpadSubtract)
            )
            row(
                key("/", RDPScanCode.numpadDivide), key("*", RDPScanCode.numpadMultiply),
                key("4", RDPScanCode.numpad4), key("5", RDPScanCode.numpad5), key("6", RDPScanCode.numpad6),
                key("+", RDPScanCode.numpadAdd)
            )
            row(
                nav("Fn") { page = .function }, key("Num", RDPScanCode.numLock), key("1", RDPScanCode.numpad1),
                key("2", RDPScanCode.numpad2), key("3", RDPScanCode.numpad3), key("⌫", RDPScanCode.backspace)
            )
            HStack(spacing: 4) {
                nav("⌨") { page = .arrows }
                unicode("=")
                key("0", RDPScanCode.numpad0)
                    .frame(maxWidth: .infinity)
                key(".", RDPScanCode.numpadDecimal)
                key("⏎", RDPScanCode.numpadEnter)
            }
        }
    }

    private var arrowsPage: some View {
        VStack(spacing: 4) {
            emptyRow
            row(empty, empty, empty, key("↑", RDPScanCode.up), empty, empty)
            row(
                nav("Fn") { page = .function }, empty, key("←", RDPScanCode.left), empty,
                key("→", RDPScanCode.right), key("⌫", RDPScanCode.backspace)
            )
            row(
                nav("123") { page = .numpad }, empty, empty, key("↓", RDPScanCode.down), empty,
                key("⏎", RDPScanCode.enter)
            )
        }
    }

    private var emptyRow: some View {
        row(empty, empty, empty, empty, empty, empty)
    }

    private var empty: some View {
        Color.clear.frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
    }

    private func row(@ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 4) {
            content()
        }
    }

    private func row<C0: View, C1: View, C2: View, C3: View, C4: View, C5: View>(
        _ c0: C0, _ c1: C1, _ c2: C2, _ c3: C3, _ c4: C4, _ c5: C5
    ) -> some View {
        HStack(spacing: 4) {
            c0.frame(maxWidth: .infinity)
            c1.frame(maxWidth: .infinity)
            c2.frame(maxWidth: .infinity)
            c3.frame(maxWidth: .infinity)
            c4.frame(maxWidth: .infinity)
            c5.frame(maxWidth: .infinity)
        }
    }

    private func key(_ title: String, _ code: UInt16) -> some View {
        Button(title) { controller.sendKeyTap(code) }
            .buttonStyle(AuxKeyStyle())
    }

    private func modifier(_ title: String, _ modifier: RDPSessionModifiers) -> some View {
        let active = controller.activeModifiers.contains(modifier)
        return Button(title) { controller.toggleModifier(modifier) }
            .buttonStyle(AuxKeyStyle(active: active))
    }

    private func nav(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(AuxKeyStyle(emphasized: true))
    }

    private func unicode(_ character: String) -> some View {
        Button(character) { controller.sendText(character) }
            .buttonStyle(AuxKeyStyle())
    }
}

private struct AuxKeyStyle: ButtonStyle {
    var active = false
    var emphasized = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .frame(maxWidth: .infinity, minHeight: 34, maxHeight: 34)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fillColor(pressed: configuration.isPressed))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private func fillColor(pressed: Bool) -> Color {
        if active { return Color.green.opacity(0.42) }
        if emphasized { return Color.blue.opacity(pressed ? 0.38 : 0.28) }
        return Color.white.opacity(pressed ? 0.22 : 0.14)
    }
}

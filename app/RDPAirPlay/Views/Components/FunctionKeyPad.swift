import SwiftUI

struct FunctionKeyPad: View {
    @ObservedObject var controller: RDPSessionController
    var compact: Bool = false

    private let navKeys: [(title: String, code: UInt16)] = [
        ("Esc", RDPScanCode.escape),
        ("Tab", RDPScanCode.tab),
        ("⌫", RDPScanCode.backspace),
        ("⏎", RDPScanCode.enter),
        ("Del", RDPScanCode.delete),
        ("Ins", RDPScanCode.insert),
        ("Home", RDPScanCode.home),
        ("End", RDPScanCode.end),
        ("PgUp", RDPScanCode.pageUp),
        ("PgDn", RDPScanCode.pageDown),
    ]

    var body: some View {
        VStack(spacing: compact ? 6 : 8) {
            keyRow(navKeys)
            arrowRow
            keyRow(RDPScanCode.functionKeys)
        }
    }

    private var arrowRow: some View {
        HStack(spacing: 6) {
            padKey("←", RDPScanCode.left)
            padKey("↑", RDPScanCode.up)
            padKey("↓", RDPScanCode.down)
            padKey("→", RDPScanCode.right)
            Button("Ctrl+Alt+Del") {
                controller.sendCtrlAltDelete()
            }
            .buttonStyle(PadKeyStyle(emphasized: true))
        }
    }

    private func keyRow(_ keys: [(title: String, code: UInt16)]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: min(keys.count, 6))
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, item in
                padKey(item.title, item.code)
            }
        }
    }

    private func padKey(_ title: String, _ code: UInt16) -> some View {
        Button(title) {
            controller.sendKeyTap(code)
        }
        .buttonStyle(PadKeyStyle())
    }
}

struct ModifierToggleBar: View {
    @ObservedObject var controller: RDPSessionController

    var body: some View {
        HStack(spacing: 6) {
            modifierButton("Ctrl", .ctrl)
            modifierButton("Alt", .alt)
            modifierButton("Shift", .shift)
            modifierButton("Win", .win)
        }
    }

    private func modifierButton(_ title: String, _ modifier: RDPSessionModifiers) -> some View {
        let active = controller.activeModifiers.contains(modifier)
        return Button(title) {
            controller.toggleModifier(modifier)
        }
        .buttonStyle(PadKeyStyle(active: active))
    }
}

struct PadKeyStyle: ButtonStyle {
    var active: Bool = false
    var emphasized: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(pressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(active ? 0.45 : 0.12), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
    }

    private func backgroundColor(pressed: Bool) -> Color {
        if active { return Color.green.opacity(0.45) }
        if emphasized { return Color.orange.opacity(pressed ? 0.45 : 0.28) }
        return Color.white.opacity(pressed ? 0.22 : 0.12)
    }
}

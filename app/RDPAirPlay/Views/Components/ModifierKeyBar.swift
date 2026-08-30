import SwiftUI

/// F-IN-05: 本机桌面模式下的修饰键 / 常用键
struct ModifierKeyBar: View {
    @ObservedObject var controller: RDPSessionController

    var body: some View {
        VStack(spacing: 6) {
            ModifierToggleBar(controller: controller)
            HStack(spacing: 6) {
                keyButton("Esc", RDPScanCode.escape)
                keyButton("Tab", RDPScanCode.tab)
                keyButton("⌫", RDPScanCode.backspace)
                keyButton("⏎", RDPScanCode.enter)
                keyButton("Del", RDPScanCode.delete)
                Button("CAD") {
                    controller.sendCtrlAltDelete()
                }
                .buttonStyle(PadKeyStyle(emphasized: true))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.75))
    }

    private func keyButton(_ title: String, _ code: UInt16) -> some View {
        Button(title) {
            controller.sendKeyTap(code)
        }
        .buttonStyle(PadKeyStyle())
    }
}

import SwiftUI

/// 内置 26 键 QWERTY，用于无第二屏时在 App 内直接输入英文
struct OnScreenKeyboardView: View {
    @ObservedObject var controller: RDPSessionController
    var onRequestSystemKeyboard: (() -> Void)?

    @State private var shiftEnabled = false

    private let row1 = Array("qwertyuiop")
    private let row2 = Array("asdfghjkl")
    private let row3 = Array("zxcvbnm")

    var body: some View {
        VStack(spacing: 5) {
            keyRow(row1)
            keyRow(row2)
            HStack(spacing: 4) {
                shiftKey
                ForEach(row3, id: \.self) { ch in
                    letterKey(ch)
                }
                backspaceKey
            }
            HStack(spacing: 4) {
                Button("123") {
                    onRequestSystemKeyboard?()
                }
                .buttonStyle(KeyboardKeyStyle(width: 44))

                Button("中文") {
                    onRequestSystemKeyboard?()
                }
                .buttonStyle(KeyboardKeyStyle(width: 44))

                Button("Space") {
                    controller.sendKeyTap(RDPScanCode.space)
                }
                .buttonStyle(KeyboardKeyStyle(flexible: true))

                Button("⏎") {
                    controller.sendKeyTap(RDPScanCode.enter)
                }
                .buttonStyle(KeyboardKeyStyle(width: 52))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(.black.opacity(0.88))
    }

    private func keyRow(_ letters: [Character]) -> some View {
        HStack(spacing: 4) {
            ForEach(letters, id: \.self) { ch in
                letterKey(ch)
            }
        }
    }

    private var shiftKey: some View {
        Button {
            shiftEnabled.toggle()
        } label: {
            Image(systemName: shiftEnabled ? "shift.fill" : "shift")
        }
        .buttonStyle(KeyboardKeyStyle(width: 44, active: shiftEnabled))
    }

    private var backspaceKey: some View {
        Button {
            controller.sendKeyTap(RDPScanCode.backspace)
        } label: {
            Image(systemName: "delete.left")
        }
        .buttonStyle(KeyboardKeyStyle(width: 44))
    }

    private func letterKey(_ character: Character) -> some View {
        let upper = shiftEnabled
        let title = String(upper ? character.uppercased() : character.lowercased())
        return Button(title) {
            sendLetter(character, shifted: upper)
        }
        .buttonStyle(KeyboardKeyStyle(flexible: true))
    }

    private func sendLetter(_ character: Character, shifted: Bool) {
        let lower = String(character).lowercased()
        guard let code = OnScreenKeyboardLayout.scanCode(for: lower) else { return }
        if shifted {
            controller.sendKeyCode(RDPScanCode.lShift, action: .down)
            controller.sendKeyTap(code)
            controller.sendKeyCode(RDPScanCode.lShift, action: .up)
        } else {
            controller.sendKeyTap(code)
        }
    }
}

private enum OnScreenKeyboardLayout {
    static func scanCode(for letter: String) -> UInt16? {
        switch letter {
        case "a": return 0x1E
        case "b": return 0x30
        case "c": return 0x2E
        case "d": return 0x20
        case "e": return 0x12
        case "f": return 0x21
        case "g": return 0x22
        case "h": return 0x23
        case "i": return 0x17
        case "j": return 0x24
        case "k": return 0x25
        case "l": return 0x26
        case "m": return 0x32
        case "n": return 0x31
        case "o": return 0x18
        case "p": return 0x19
        case "q": return 0x10
        case "r": return 0x13
        case "s": return 0x1F
        case "t": return 0x14
        case "u": return 0x16
        case "v": return 0x2F
        case "w": return 0x11
        case "x": return 0x2D
        case "y": return 0x15
        case "z": return 0x2C
        default: return nil
        }
    }
}

private struct KeyboardKeyStyle: ButtonStyle {
    var width: CGFloat?
    var flexible = false
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        Group {
            if flexible {
                configuration.label
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            } else {
                configuration.label
                    .frame(width: width, height: 38)
            }
        }
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(.white)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(active ? Color.green.opacity(0.4) : Color.white.opacity(configuration.isPressed ? 0.24 : 0.14))
        )
        .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

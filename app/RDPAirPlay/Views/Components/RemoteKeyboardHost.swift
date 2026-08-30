import SwiftUI
import UIKit

/// 系统软键盘：组字完成后发 Unicode，退格/回车走 RDP 扫描码
struct RemoteKeyboardHost: UIViewRepresentable {
    @Binding var isActive: Bool
    var onInsert: (String) -> Void
    var onDelete: () -> Void
    var onReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> KeyboardCaptureField {
        let field = KeyboardCaptureField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.returnKeyType = .default
        field.textContentType = nil
        field.backgroundColor = .clear
        field.textColor = .clear
        field.tintColor = .clear
        field.borderStyle = .none
        field.inputAssistantItem.leadingBarButtonGroups = []
        field.inputAssistantItem.trailingBarButtonGroups = []
        field.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.field = field
        return field
    }

    func updateUIView(_ uiView: KeyboardCaptureField, context: Context) {
        context.coordinator.parent = self
        // 帧刷新会高频触发 updateUIView；仅在激活状态变化时改 first responder，
        // 否则中文/系统 IME 会反复重建并卡死主线程。
        context.coordinator.applyActiveState(isActive, to: uiView)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RemoteKeyboardHost
        weak var field: KeyboardCaptureField?
        private var appliedActive: Bool?

        init(parent: RemoteKeyboardHost) {
            self.parent = parent
        }

        func applyActiveState(_ active: Bool, to field: KeyboardCaptureField) {
            guard appliedActive != active else { return }
            appliedActive = active
            if active {
                DispatchQueue.main.async {
                    if !field.isFirstResponder {
                        field.becomeFirstResponder()
                    }
                }
            } else if field.isFirstResponder {
                field.resignFirstResponder()
            }
        }

        @objc func editingChanged(_ textField: UITextField) {
            flushCommittedText(textField)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string == "\n" {
                flushCommittedText(textField)
                dispatchReturn()
                return false
            }
            if string.isEmpty, (textField.text ?? "").isEmpty, textField.markedTextRange == nil {
                dispatchDelete()
                return false
            }
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            flushCommittedText(textField)
            dispatchReturn()
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            flushCommittedText(textField)
        }

        private func dispatchInsert(_ text: String) {
            let handler = parent.onInsert
            DispatchQueue.main.async {
                handler(text)
            }
        }

        private func dispatchDelete() {
            let handler = parent.onDelete
            DispatchQueue.main.async {
                handler()
            }
        }

        private func dispatchReturn() {
            let handler = parent.onReturn
            DispatchQueue.main.async {
                handler()
            }
        }

        private func flushCommittedText(_ textField: UITextField) {
            guard textField.markedTextRange == nil, let text = textField.text, !text.isEmpty else { return }
            textField.text = ""
            dispatchInsert(text)
        }
    }
}

final class KeyboardCaptureField: UITextField {
    override var canBecomeFirstResponder: Bool { true }

    override func caretRect(for position: UITextPosition) -> CGRect { .zero }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }

    /// 避免隐藏 TextField 被选中时弹出放大镜 / 选择菜单干扰 IME
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool { false }
}

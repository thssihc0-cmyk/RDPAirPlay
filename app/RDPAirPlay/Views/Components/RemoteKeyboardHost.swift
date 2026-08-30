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
        if isActive {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: RemoteKeyboardHost
        weak var field: KeyboardCaptureField?

        init(parent: RemoteKeyboardHost) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            flushCommittedText(textField)
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            if string == "\n" {
                flushCommittedText(textField)
                parent.onReturn()
                return false
            }
            if string.isEmpty, (textField.text ?? "").isEmpty, textField.markedTextRange == nil {
                parent.onDelete()
                return false
            }
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            flushCommittedText(textField)
            parent.onReturn()
            return false
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            flushCommittedText(textField)
            if parent.isActive {
                parent.isActive = false
            }
        }

        private func flushCommittedText(_ textField: UITextField) {
            guard textField.markedTextRange == nil, let text = textField.text, !text.isEmpty else { return }
            parent.onInsert(text)
            textField.text = ""
        }
    }
}

final class KeyboardCaptureField: UITextField {
    override var canBecomeFirstResponder: Bool { true }

    override func caretRect(for position: UITextPosition) -> CGRect { .zero }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
}

import UIKit

enum HardwareKeyboardMapper {
    static func rdpScanCode(for key: UIKey) -> UInt16? {
        rdpScanCode(forHIDUsage: key.keyCode)
    }

    static func rdpScanCode(forHIDUsage usage: UIKeyboardHIDUsage) -> UInt16? {
        switch usage {
        case .keyboardA: return 0x1E
        case .keyboardB: return 0x30
        case .keyboardC: return 0x2E
        case .keyboardD: return 0x20
        case .keyboardE: return 0x12
        case .keyboardF: return 0x21
        case .keyboardG: return 0x22
        case .keyboardH: return 0x23
        case .keyboardI: return 0x17
        case .keyboardJ: return 0x24
        case .keyboardK: return 0x25
        case .keyboardL: return 0x26
        case .keyboardM: return 0x32
        case .keyboardN: return 0x31
        case .keyboardO: return 0x18
        case .keyboardP: return 0x19
        case .keyboardQ: return 0x10
        case .keyboardR: return 0x13
        case .keyboardS: return 0x1F
        case .keyboardT: return 0x14
        case .keyboardU: return 0x16
        case .keyboardV: return 0x2F
        case .keyboardW: return 0x11
        case .keyboardX: return 0x2D
        case .keyboardY: return 0x15
        case .keyboardZ: return 0x2C
        case .keyboard1: return 0x02
        case .keyboard2: return 0x03
        case .keyboard3: return 0x04
        case .keyboard4: return 0x05
        case .keyboard5: return 0x06
        case .keyboard6: return 0x07
        case .keyboard7: return 0x08
        case .keyboard8: return 0x09
        case .keyboard9: return 0x0A
        case .keyboard0: return 0x0B
        case .keyboardReturnOrEnter: return RDPScanCode.enter
        case .keyboardEscape: return RDPScanCode.escape
        case .keyboardDeleteOrBackspace: return RDPScanCode.backspace
        case .keyboardTab: return RDPScanCode.tab
        case .keyboardSpacebar: return RDPScanCode.space
        case .keyboardHyphen: return 0x0C
        case .keyboardEqualSign: return 0x0D
        case .keyboardOpenBracket: return 0x1A
        case .keyboardCloseBracket: return 0x1B
        case .keyboardBackslash: return 0x2B
        case .keyboardSemicolon: return 0x27
        case .keyboardQuote: return 0x28
        case .keyboardGraveAccentAndTilde: return 0x29
        case .keyboardComma: return 0x33
        case .keyboardPeriod: return 0x34
        case .keyboardSlash: return 0x35
        case .keyboardCapsLock: return 0x3A
        case .keyboardF1: return RDPScanCode.f1
        case .keyboardF2: return RDPScanCode.f2
        case .keyboardF3: return RDPScanCode.f3
        case .keyboardF4: return RDPScanCode.f4
        case .keyboardF5: return RDPScanCode.f5
        case .keyboardF6: return RDPScanCode.f6
        case .keyboardF7: return RDPScanCode.f7
        case .keyboardF8: return RDPScanCode.f8
        case .keyboardF9: return RDPScanCode.f9
        case .keyboardF10: return RDPScanCode.f10
        case .keyboardF11: return RDPScanCode.f11
        case .keyboardF12: return RDPScanCode.f12
        case .keyboardHome: return RDPScanCode.home
        case .keyboardPageUp: return RDPScanCode.pageUp
        case .keyboardDeleteForward: return RDPScanCode.delete
        case .keyboardEnd: return RDPScanCode.end
        case .keyboardPageDown: return RDPScanCode.pageDown
        case .keyboardRightArrow: return RDPScanCode.right
        case .keyboardLeftArrow: return RDPScanCode.left
        case .keyboardDownArrow: return RDPScanCode.down
        case .keyboardUpArrow: return RDPScanCode.up
        case .keyboardInsert: return RDPScanCode.insert
        case .keyboardLeftControl: return RDPScanCode.lControl
        case .keyboardLeftShift: return RDPScanCode.lShift
        case .keyboardLeftAlt: return RDPScanCode.lAlt
        case .keyboardLeftGUI: return RDPScanCode.lWin
        case .keyboardRightControl: return 0x11D
        case .keyboardRightShift: return 0x36
        case .keyboardRightAlt: return 0x138
        case .keyboardRightGUI: return 0x15C
        default:
            return nil
        }
    }
}

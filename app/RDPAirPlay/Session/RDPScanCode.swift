import Foundation

/// FreeRDP / Windows RDP scancode（含 KBDEXT=0x100）
enum RDPScanCode {
    static let escape: UInt16 = 0x01
    static let backspace: UInt16 = 0x0E
    static let tab: UInt16 = 0x0F
    static let enter: UInt16 = 0x1C
    static let lControl: UInt16 = 0x1D
    static let lShift: UInt16 = 0x2A
    static let lAlt: UInt16 = 0x38
    static let space: UInt16 = 0x39
    static let f1: UInt16 = 0x3B
    static let f2: UInt16 = 0x3C
    static let f3: UInt16 = 0x3D
    static let f4: UInt16 = 0x3E
    static let f5: UInt16 = 0x3F
    static let f6: UInt16 = 0x40
    static let f7: UInt16 = 0x41
    static let f8: UInt16 = 0x42
    static let f9: UInt16 = 0x43
    static let f10: UInt16 = 0x44
    static let f11: UInt16 = 0x57
    static let f12: UInt16 = 0x58

    static let home: UInt16 = 0x147
    static let up: UInt16 = 0x148
    static let pageUp: UInt16 = 0x149
    static let left: UInt16 = 0x14B
    static let right: UInt16 = 0x14D
    static let end: UInt16 = 0x14F
    static let down: UInt16 = 0x150
    static let pageDown: UInt16 = 0x151
    static let insert: UInt16 = 0x152
    static let delete: UInt16 = 0x153
    static let lWin: UInt16 = 0x15B
    static let apps: UInt16 = 0x15D
    static let printScreen: UInt16 = 0x137
    static let numLock: UInt16 = 0x145
    static let numpad0: UInt16 = 0x52
    static let numpad1: UInt16 = 0x4F
    static let numpad2: UInt16 = 0x50
    static let numpad3: UInt16 = 0x51
    static let numpad4: UInt16 = 0x4B
    static let numpad5: UInt16 = 0x4C
    static let numpad6: UInt16 = 0x4D
    static let numpad7: UInt16 = 0x47
    static let numpad8: UInt16 = 0x48
    static let numpad9: UInt16 = 0x49
    static let numpadAdd: UInt16 = 0x4E
    static let numpadSubtract: UInt16 = 0x4A
    static let numpadMultiply: UInt16 = 0x37
    static let numpadDivide: UInt16 = 0x135
    static let numpadDecimal: UInt16 = 0x53
    static let numpadEnter: UInt16 = 0x11C

    static let functionKeys: [(title: String, code: UInt16)] = [
        ("F1", f1), ("F2", f2), ("F3", f3), ("F4", f4),
        ("F5", f5), ("F6", f6), ("F7", f7), ("F8", f8),
        ("F9", f9), ("F10", f10), ("F11", f11), ("F12", f12),
    ]
}

extension RDPSessionModifiers {
    var scanCode: UInt16 {
        if self == .ctrl { return RDPScanCode.lControl }
        if self == .alt { return RDPScanCode.lAlt }
        if self == .shift { return RDPScanCode.lShift }
        if self == .win { return RDPScanCode.lWin }
        return 0
    }
}

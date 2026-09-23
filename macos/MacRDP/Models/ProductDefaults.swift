import Foundation

/// Frozen product defaults (Jack confirmed 2026-09-23). Do not re-ask.
enum ProductDefaults {
    /// R1
    static let minimumMacOS = "13.0"
    /// R1: Apple Silicon primary; Intel best-effort
    static let primaryArchNote = "Apple Silicon primary; Intel best-effort"

    /// R2
    static let minimumRDP = "8.1+"
    static let nlaDefaultEnabled = true
    /// UDP best-effort — never hard-fail MVP if unavailable
    static let udpHardFail = false

    /// R3: qualitative weak-net acceptance for now
    static let weakNetAcceptance = "qualitative"

    /// R4
    static let clipboardScope = "text+image"
    static let driveMapScope = "user-selected folders"
    static let microphoneInMVP = false // P1

    /// R5
    static let multiMonitorPriority = "P1"
    static let printerPriority = "P2"

    /// Weak-net scheme: A primary + 三色 + input-first + reconnect; evaluate B (UDP)
    static let weakNetScheme = "A+三色+input-first+reconnect; evaluate UDP(B)"
}

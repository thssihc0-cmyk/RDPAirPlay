import AppKit
import CoreGraphics
import Foundation

struct RDPConnectionOptions: Equatable {
    let hostname: String
    let port: Int
    let username: String
    let password: String
    let width: Int
    let height: Int
    let enableNLA: Bool
    let enableSpeaker: Bool
    let optimizeForSpeed: Bool
}

struct RDPMouseEvent {
    enum Button { case left, right }
    enum Action {
        case down
        case up
        case move
        case scroll(deltaX: Int, deltaY: Int)
    }

    let x: Int
    let y: Int
    let button: Button
    let action: Action
}

struct RDPKeyEvent {
    enum Action { case down, up }
    let keyCode: UInt16
    let action: Action
    let modifiers: RDPSessionModifiers
}

struct RDPSessionModifiers: OptionSet {
    let rawValue: UInt8
    static let ctrl = RDPSessionModifiers(rawValue: 1 << 0)
    static let alt = RDPSessionModifiers(rawValue: 1 << 1)
    static let shift = RDPSessionModifiers(rawValue: 1 << 2)
    static let win = RDPSessionModifiers(rawValue: 1 << 3)
}

struct RDPFrame {
    let width: Int
    let height: Int
    let image: NSImage?
    let timestamp: TimeInterval
}

struct RDPCursor {
    var image: NSImage?
    var hotspot: CGPoint
    var position: CGPoint
    var visible: Bool
}

protocol RDPSessionHandling: AnyObject {
    var delegate: RDPSessionDelegate? { get set }
    func connect(options: RDPConnectionOptions) async throws
    func disconnect() async
    func setResolution(width: Int, height: Int) async throws
    func sendMouse(_ event: RDPMouseEvent)
    func sendKey(_ event: RDPKeyEvent)
    func sendUnicodeText(_ text: String)
}

protocol RDPSessionDelegate: AnyObject {
    func sessionDidConnect()
    func sessionDidDisconnect(error: RDPConnectionError?)
    func sessionDidReceiveFrame(_ frame: RDPFrame)
    func sessionDidReceiveCursor(_ cursor: RDPCursor)
    func sessionDidUpdateMetrics(rttMs: Double, lossPercent: Double, kbps: Int)
}

enum RDPSessionFactory {
    static func makeSession(preferNative: Bool = RDPBridge.isAvailable) -> RDPSessionHandling {
        if preferNative {
            return NativeRDPSession()
        }
        return StubRDPSession()
    }
}

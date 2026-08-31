import CoreGraphics
import Foundation
import UIKit

struct RDPConnectionOptions: Equatable {
    let hostname: String
    let port: Int
    let username: String
    let password: String
    let width: Int
    let height: Int
    let enableNLA: Bool
    let enableSpeaker: Bool
    let enableMicrophone: Bool
    /// 速度优先：通知 Windows 关闭壁纸、拖动阴影与过渡动画
    let optimizeForSpeed: Bool
}

struct RDPMouseEvent {
    enum Button {
        case left
        case right
    }

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
    enum Action {
        case down
        case up
    }

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

/// 远程帧（Stub 用 UIImage；FreeRDP 集成后可改为 Metal 纹理 / CMSampleBuffer）
struct RDPFrame {
    let width: Int
    let height: Int
    let image: UIImage?
    let timestamp: TimeInterval
}

struct RDPCursor {
    var image: UIImage?
    var hotspot: CGPoint
    var position: CGPoint
    var visible: Bool
    /// 仅更新指针图像/热点，不包含可靠的位置同步（RDP Pointer_Set 会携带滞后坐标）
    var updatesImageOnly: Bool = false

    static let hidden = RDPCursor(image: nil, hotspot: .zero, position: .zero, visible: false, updatesImageOnly: false)

    static func defaultArrow(at position: CGPoint) -> RDPCursor {
        RDPCursor(image: arrowImage, hotspot: CGPoint(x: 1, y: 1), position: position, visible: true, updatesImageOnly: false)
    }

    static var arrowImage: UIImage {
        let size = CGSize(width: 12, height: 20)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0.5, y: 0.5))
            path.addLine(to: CGPoint(x: 0.5, y: 16.5))
            path.addLine(to: CGPoint(x: 4.5, y: 13.0))
            path.addLine(to: CGPoint(x: 7.5, y: 19.0))
            path.addLine(to: CGPoint(x: 9.5, y: 18.0))
            path.addLine(to: CGPoint(x: 6.2, y: 12.2))
            path.addLine(to: CGPoint(x: 11.0, y: 12.2))
            path.close()
            UIColor.black.setStroke()
            UIColor.white.setFill()
            path.lineWidth = 1
            path.fill()
            path.stroke()
        }
    }
}

/// RDP 会话抽象，FreeRDP 实现与 Stub 共用
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
    static func makeSession(useNativeBridge: Bool = RDPBridge.isAvailable) -> RDPSessionHandling {
        if useNativeBridge {
            return NativeRDPSession()
        }
        return StubRDPSession()
    }
}

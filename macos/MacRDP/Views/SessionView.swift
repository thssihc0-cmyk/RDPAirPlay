import AppKit
import SwiftUI

struct SessionView: View {
    @ObservedObject var controller: RDPSessionController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(controller.state.label)
                    .font(.headline)
                Text(controller.statusLine)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(controller.metricsText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Picker("色彩", selection: $controller.colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .frame(width: 120)
                .disabled(controller.lockColorMode)
                Toggle("锁色", isOn: $controller.lockColorMode)
                    .toggleStyle(.checkbox)
                Text(controller.weakNetTier.displayName)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Button("断开") {
                    Task { await controller.disconnect() }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)

            RemoteDesktopCanvas(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// F-DISP-01 + F-IN-01: 远程画面 + 鼠标/键盘
struct RemoteDesktopCanvas: NSViewRepresentable {
    @ObservedObject var controller: RDPSessionController

    func makeNSView(context: Context) -> RemoteDesktopNSView {
        let view = RemoteDesktopNSView()
        view.controller = controller
        return view
    }

    func updateNSView(_ nsView: RemoteDesktopNSView, context: Context) {
        nsView.controller = controller
        nsView.image = controller.displayImage
        nsView.needsDisplay = true
    }
}

final class RemoteDesktopNSView: NSView {
    weak var controller: RDPSessionController?
    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        guard let image else { return }
        let fitted = aspectFit(image.size, in: bounds.size)
        image.draw(in: fitted)
    }

    override func mouseDown(with event: NSEvent) { sendMouse(event, button: .left, action: .down) }
    override func mouseUp(with event: NSEvent) { sendMouse(event, button: .left, action: .up) }
    override func rightMouseDown(with event: NSEvent) { sendMouse(event, button: .right, action: .down) }
    override func rightMouseUp(with event: NSEvent) { sendMouse(event, button: .right, action: .up) }
    override func mouseDragged(with event: NSEvent) { sendMouse(event, button: .left, action: .move) }
    override func mouseMoved(with event: NSEvent) { sendMouse(event, button: .left, action: .move) }

    override func scrollWheel(with event: NSEvent) {
        let point = remotePoint(from: event)
        controller?.sendMouse(
            at: point,
            button: .left,
            action: .scroll(deltaX: Int(event.scrollingDeltaX), deltaY: Int(event.scrollingDeltaY))
        )
    }

    override func keyDown(with event: NSEvent) {
        if let chars = event.characters, !chars.isEmpty, !event.modifierFlags.contains(.command) {
            // IME / Unicode path (F-IN-03 方向)
            let isPrintable = chars.unicodeScalars.contains { !$0.properties.isASCIIHexDigit && $0.value >= 32 } || chars.count > 1
            if event.keyCode == 51 || event.keyCode == 36 || event.keyCode == 48 {
                controller?.sendKey(keyCode: UInt16(event.keyCode), down: true, modifiers: modifiers(from: event))
            } else if isPrintable || chars.unicodeScalars.contains(where: { $0.value > 127 }) {
                controller?.sendText(chars)
                return
            }
        }
        controller?.sendKey(keyCode: UInt16(event.keyCode), down: true, modifiers: modifiers(from: event))
    }

    override func keyUp(with event: NSEvent) {
        controller?.sendKey(keyCode: UInt16(event.keyCode), down: false, modifiers: modifiers(from: event))
    }

    override func updateTrackingAreas() {
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    private func sendMouse(_ event: NSEvent, button: RDPMouseEvent.Button, action: RDPMouseEvent.Action) {
        controller?.sendMouse(at: remotePoint(from: event), button: button, action: action)
    }

    private func remotePoint(from event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        guard let image else { return local }
        let fitted = aspectFit(image.size, in: bounds.size)
        let x = (local.x - fitted.minX) / fitted.width * image.size.width
        let y = (local.y - fitted.minY) / fitted.height * image.size.height
        return CGPoint(
            x: max(0, min(image.size.width, x)),
            y: max(0, min(image.size.height, y))
        )
    }

    private func aspectFit(_ imageSize: CGSize, in container: CGSize) -> CGRect {
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }

    private func modifiers(from event: NSEvent) -> RDPSessionModifiers {
        var m: RDPSessionModifiers = []
        if event.modifierFlags.contains(.control) { m.insert(.ctrl) }
        if event.modifierFlags.contains(.option) { m.insert(.alt) }
        if event.modifierFlags.contains(.shift) { m.insert(.shift) }
        if event.modifierFlags.contains(.command) { m.insert(.win) }
        return m
    }
}

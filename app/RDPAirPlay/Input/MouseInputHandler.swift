import UIKit

/// 蓝牙鼠标 / 触控板指针（iOS 13.4+ indirect pointer）输入
final class MouseInputHandler: NSObject, UIGestureRecognizerDelegate, UIPointerInteractionDelegate {
    weak var controller: RDPSessionController?
    var desktopSizeProvider: (() -> CGSize)?

    private weak var hostView: UIView?
    private var pointerIsIndirect = false
    private var mouseDragActive = false
    private var hoverRecognizer: UIHoverGestureRecognizer?
    private var scrollRecognizer: UIPanGestureRecognizer?
    private var pointerInteraction: UIPointerInteraction?

    func attach(to view: UIView) {
        hostView = view

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        view.addGestureRecognizer(hover)
        hoverRecognizer = hover

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.delegate = self
        view.addGestureRecognizer(scroll)
        scrollRecognizer = scroll

        let secondaryTap = UITapGestureRecognizer(target: self, action: #selector(handleSecondaryTap(_:)))
        secondaryTap.buttonMaskRequired = .secondary
        secondaryTap.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        secondaryTap.delegate = self
        view.addGestureRecognizer(secondaryTap)

        let pointer = UIPointerInteraction(delegate: self)
        view.addInteraction(pointer)
        pointerInteraction = pointer
    }

    func handleIndirectPanBegan(at point: CGPoint) {
        movePointer(to: point)
        controller?.sendMouseButton(.left, down: true)
        mouseDragActive = true
    }

    func handleIndirectPanChanged(to point: CGPoint) {
        movePointer(to: point)
    }

    func handleIndirectPanEnded() {
        if mouseDragActive {
            controller?.sendMouseButton(.left, down: false)
            mouseDragActive = false
        }
    }

    func shouldReceiveTouch(_ touch: UITouch, for gestureRecognizer: UIGestureRecognizer) -> Bool {
        pointerIsIndirect = touch.type == .indirectPointer
        if let scrollRecognizer, gestureRecognizer === scrollRecognizer {
            return false
        }
        if pointerIsIndirect, gestureRecognizer is UILongPressGestureRecognizer {
            return false
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        shouldReceiveTouch(touch, for: gestureRecognizer)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let panAndLongPress =
            (gestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer is UILongPressGestureRecognizer) ||
            (gestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer is UIPanGestureRecognizer)
        return panAndLongPress
    }

    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        .hidden()
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        movePointer(to: gesture.location(in: hostView))
    }

    @objc private func handleSecondaryTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: hostView)
        movePointer(to: point)
        controller?.sendClick(at: point, desktopSize: currentDesktopSize, button: .right)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .changed else { return }
        let deltaY = Int(-gesture.translation(in: hostView).y / 8)
        guard deltaY != 0 else { return }
        controller?.sendScrollAtCursor(deltaY: deltaY)
        gesture.setTranslation(.zero, in: hostView)
    }

    func handleIndirectTap(at point: CGPoint) {
        movePointer(to: point)
        controller?.sendClick(at: point, desktopSize: currentDesktopSize, button: .left)
    }

    var usesIndirectPointer: Bool { pointerIsIndirect }

    private var currentDesktopSize: CGSize {
        desktopSizeProvider?() ?? hostView?.bounds.size ?? .zero
    }

    private func movePointer(to point: CGPoint) {
        controller?.sendMouseMove(to: point, desktopSize: currentDesktopSize)
    }
}

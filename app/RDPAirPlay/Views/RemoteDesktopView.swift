import SwiftUI
import UIKit

/// F-DISP-03 / F-DISP-05 / F-IN-01 / F-IN-03: 远程画面（Microsoft Remote Desktop 手势）
struct RemoteDesktopView: View {
    @ObservedObject var controller: RDPSessionController
    var interactionEnabled: Bool = true

    var body: some View {
        RemoteDesktopCanvasRepresentable(controller: controller, interactionEnabled: interactionEnabled)
            .background(Color.black)
    }
}

private struct RemoteDesktopCanvasRepresentable: UIViewRepresentable {
    @ObservedObject var controller: RDPSessionController
    let interactionEnabled: Bool

    func makeUIView(context: Context) -> RemoteDesktopCanvasView {
        let view = RemoteDesktopCanvasView()
        view.controller = controller
        view.isUserInteractionEnabled = interactionEnabled
        return view
    }

    func updateUIView(_ uiView: RemoteDesktopCanvasView, context: Context) {
        uiView.controller = controller
        uiView.isUserInteractionEnabled = interactionEnabled
        uiView.updateContent(
            image: processedImage(from: controller),
            cursor: controller.cursor,
            mouseMode: controller.mouseMode,
            viewportScale: controller.viewportScale,
            viewportOffset: controller.viewportOffset,
            viewportFocalContent: controller.viewportFocalContent,
            viewportFocalScreen: controller.viewportFocalScreen
        )
    }

    private func processedImage(from controller: RDPSessionController) -> UIImage? {
        guard let frame = controller.latestFrame, let image = frame.image else { return nil }
        if controller.colorMode == .fullColor { return image }
        guard let cg = image.cgImage,
              let processed = ColorModeProcessor.apply(controller.colorMode, to: cg) else {
            return image
        }
        return UIImage(cgImage: processed)
    }
}

/// UIKit 画布：缩放/平移与 Microsoft Remote Desktop 触控模式一致
final class RemoteDesktopCanvasView: UIView, UIGestureRecognizerDelegate {
    var controller: RDPSessionController? {
        didSet { mouseHandler.controller = controller }
    }

    private let contentView = UIView()
    private let imageView = UIImageView()
    private let cursorView = UIImageView()
    private let placeholderLabel = UILabel()
    private let mouseHandler = MouseInputHandler()

    private var fitRect: CGRect = .zero
    private var desktopPixelSize = CGSize(width: 16, height: 9)
    private var pinchBaseScale: CGFloat = 1
    private var pinchBaseOffset = CGSize.zero
    private var pinchAnchorInContent = CGPoint.zero
    private var panBaseOffset = CGSize.zero
    private var pointerIsIndirect = false
    private var currentCursor = RDPCursor.hidden
    private var mouseMode: RemoteMouseMode = .mousePointer
    private var lastCursorDragPoint = CGPoint.zero

    private weak var viewportPanRecognizer: UIPanGestureRecognizer?
    private weak var mousePanRecognizer: UIPanGestureRecognizer?
    private weak var cursorMoveRecognizer: UILongPressGestureRecognizer?
    private weak var twoFingerTapRecognizer: UITapGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isMultipleTouchEnabled = true

        contentView.backgroundColor = .clear
        addSubview(contentView)

        imageView.contentMode = .scaleToFill
        imageView.backgroundColor = .black
        contentView.addSubview(imageView)

        cursorView.contentMode = .topLeft
        cursorView.backgroundColor = .clear
        cursorView.isOpaque = false
        cursorView.isUserInteractionEnabled = false
        addSubview(cursorView)

        placeholderLabel.text = "等待画面…"
        placeholderLabel.textColor = UIColor(white: 1, alpha: 0.65)
        placeholderLabel.font = .preferredFont(forTextStyle: .body)
        placeholderLabel.textAlignment = .center
        addSubview(placeholderLabel)

        mouseHandler.attach(to: self)
        mouseHandler.desktopSizeProvider = { [weak self] in self?.fitRect.size ?? .zero }
        installGestures()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeholderLabel.frame = bounds
        contentView.frame = bounds
        recalculateFitRect()
        applyViewportTransform()
        layoutImageAndCursor()
    }

    func updateContent(
        image: UIImage?,
        cursor: RDPCursor,
        mouseMode: RemoteMouseMode,
        viewportScale: CGFloat,
        viewportOffset: CGSize,
        viewportFocalContent: CGPoint,
        viewportFocalScreen: CGPoint
    ) {
        currentCursor = cursor
        self.mouseMode = mouseMode
        _ = viewportScale
        _ = viewportOffset
        _ = viewportFocalContent
        _ = viewportFocalScreen
        if let image {
            imageView.image = image
            desktopPixelSize = image.size
            placeholderLabel.isHidden = true
            imageView.isHidden = false
        } else {
            imageView.image = nil
            placeholderLabel.isHidden = false
            imageView.isHidden = true
            cursorView.isHidden = true
        }
        applyViewportTransform()
        layoutImageAndCursor()
    }

    private func recalculateFitRect() {
        guard desktopPixelSize.width > 0, desktopPixelSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            fitRect = bounds
            return
        }
        let scale = min(bounds.width / desktopPixelSize.width, bounds.height / desktopPixelSize.height)
        let size = CGSize(width: desktopPixelSize.width * scale, height: desktopPixelSize.height * scale)
        fitRect = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func applyViewportTransform() {
        guard let controller else {
            contentView.transform = .identity
            return
        }
        contentView.transform = viewportTransform(for: controller)
    }

    /// 鼠标指针模式：画面围绕光标锚点缩放；直接触控：围绕视图中心
    private func viewportTransform(for controller: RDPSessionController) -> CGAffineTransform {
        let scale = controller.viewportScale
        let offset = controller.viewportOffset

        if mouseMode == .mousePointer, scale > 1.001 {
            let focal = controller.viewportFocalContent
            let focalScreen = CGPoint(
                x: controller.viewportFocalScreen.x + offset.width,
                y: controller.viewportFocalScreen.y + offset.height
            )
            var transform = CGAffineTransform(translationX: focalScreen.x, y: focalScreen.y)
            transform = transform.scaledBy(x: scale, y: scale)
            transform = transform.translatedBy(x: -focal.x, y: -focal.y)
            return transform
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: center.x + offset.width, y: center.y + offset.height)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -center.x, y: -center.y)
        return transform
    }

    private func contentToScreen(_ point: CGPoint) -> CGPoint {
        guard let controller else { return point }
        let scale = controller.viewportScale
        let offset = controller.viewportOffset

        if mouseMode == .mousePointer, scale > 1.001 {
            let focal = controller.viewportFocalContent
            let focalScreen = CGPoint(
                x: controller.viewportFocalScreen.x + offset.width,
                y: controller.viewportFocalScreen.y + offset.height
            )
            return CGPoint(
                x: (point.x - focal.x) * scale + focalScreen.x,
                y: (point.y - focal.y) * scale + focalScreen.y
            )
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return CGPoint(
            x: (point.x - center.x) * scale + center.x + offset.width,
            y: (point.y - center.y) * scale + center.y + offset.height
        )
    }

    private func screenToContent(_ point: CGPoint) -> CGPoint {
        guard let controller else { return point }
        let scale = max(controller.viewportScale, 0.001)
        let offset = controller.viewportOffset

        if mouseMode == .mousePointer, scale > 1.001 {
            let focal = controller.viewportFocalContent
            let focalScreen = CGPoint(
                x: controller.viewportFocalScreen.x + offset.width,
                y: controller.viewportFocalScreen.y + offset.height
            )
            return CGPoint(
                x: (point.x - focalScreen.x) / scale + focal.x,
                y: (point.y - focalScreen.y) / scale + focal.y
            )
        }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        return CGPoint(
            x: (point.x - center.x - offset.width) / scale + center.x,
            y: (point.y - center.y - offset.height) / scale + center.y
        )
    }

    private func layoutImageAndCursor() {
        imageView.frame = fitRect

        guard mouseMode == .mousePointer, currentCursor.visible,
              let frame = cursorFrameInContent() else {
            cursorView.isHidden = true
            return
        }

        let image = currentCursor.image ?? RDPCursor.arrowImage
        cursorView.image = image
        cursorView.isHidden = false

        let screenOrigin = contentToScreen(frame.origin)
        cursorView.frame = CGRect(origin: screenOrigin, size: frame.size)
        bringSubviewToFront(cursorView)
    }

    private func cursorFrameInContent() -> CGRect? {
        guard fitRect.width > 1, fitRect.height > 1,
              desktopPixelSize.width > 1, desktopPixelSize.height > 1 else { return nil }

        let pos = currentCursor.position
        let hotspot = currentCursor.hotspot
        let image = currentCursor.image ?? RDPCursor.arrowImage
        let scaleX = fitRect.width / desktopPixelSize.width
        let scaleY = fitRect.height / desktopPixelSize.height
        let w = max(image.size.width * scaleX, 1)
        let h = max(image.size.height * scaleY, 1)
        return CGRect(
            x: fitRect.minX + (pos.x - hotspot.x) * scaleX,
            y: fitRect.minY + (pos.y - hotspot.y) * scaleY,
            width: w,
            height: h
        )
    }

    private func cursorCenterInContentView() -> CGPoint? {
        guard let frame = cursorFrameInContent() else { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private func installGestures() {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        let viewportPan = UIPanGestureRecognizer(target: self, action: #selector(handleViewportPan(_:)))
        viewportPan.minimumNumberOfTouches = 1
        viewportPan.maximumNumberOfTouches = 1
        viewportPan.delegate = self
        addGestureRecognizer(viewportPan)
        viewportPanRecognizer = viewportPan

        let cursorMove = UILongPressGestureRecognizer(target: self, action: #selector(handleCursorMove(_:)))
        cursorMove.minimumPressDuration = 0.12
        cursorMove.allowableMovement = 10_000
        cursorMove.delegate = self
        addGestureRecognizer(cursorMove)
        cursorMoveRecognizer = cursorMove

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.delegate = self
        addGestureRecognizer(tap)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        tap.require(toFail: doubleTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.delegate = self
        addGestureRecognizer(longPress)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.delegate = self
        addGestureRecognizer(twoFingerTap)
        twoFingerTapRecognizer = twoFingerTap

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleTwoFingerScroll(_:)))
        scroll.minimumNumberOfTouches = 2
        scroll.delegate = self
        addGestureRecognizer(scroll)

        let mousePan = UIPanGestureRecognizer(target: self, action: #selector(handleMousePan(_:)))
        mousePan.minimumNumberOfTouches = 1
        mousePan.maximumNumberOfTouches = 1
        mousePan.delegate = self
        addGestureRecognizer(mousePan)
        mousePanRecognizer = mousePan

        tap.require(toFail: cursorMove)
        longPress.require(toFail: cursorMove)
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === viewportPanRecognizer {
            return canPanViewport && !pointerIsIndirect
        }
        if gestureRecognizer === cursorMoveRecognizer {
            return mouseMode == .mousePointer && !canPanViewport && !pointerIsIndirect
        }
        if gestureRecognizer === mousePanRecognizer {
            return pointerIsIndirect
        }
        if gestureRecognizer === twoFingerTapRecognizer {
            return mouseMode == .mousePointer && !pointerIsIndirect
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        pointerIsIndirect = touch.type == .indirectPointer
        if pointerIsIndirect, gestureRecognizer is UILongPressGestureRecognizer {
            return false
        }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer, pan.minimumNumberOfTouches == 2 {
            return !pointerIsIndirect
        }
        if gestureRecognizer is UIPanGestureRecognizer, pointerIsIndirect {
            return mouseHandler.gestureRecognizer(gestureRecognizer, shouldReceive: touch)
        }
        return mouseHandler.gestureRecognizer(gestureRecognizer, shouldReceive: touch)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let controller else { return }
        let viewCenter = CGPoint(x: bounds.midX, y: bounds.midY)

        switch gesture.state {
        case .began:
            pinchBaseScale = controller.viewportScale
            pinchBaseOffset = controller.viewportOffset

            if mouseMode == .mousePointer {
                let focalContent = cursorCenterInContentView() ?? viewCenter
                let focalScreen = contentToScreen(focalContent)
                controller.viewportFocalContent = focalContent
                controller.viewportFocalScreen = focalScreen
                pinchAnchorInContent = focalContent
            } else {
                pinchAnchorInContent = screenToContent(gesture.location(in: self))
            }
        case .changed:
            let newScale = min(max(pinchBaseScale * gesture.scale, 1), 4)

            if mouseMode == .mousePointer {
                controller.viewportScale = newScale
                controller.viewportOffset = pinchBaseOffset
            } else {
                let deltaScale = pinchBaseScale - newScale
                controller.viewportScale = newScale
                controller.viewportOffset = CGSize(
                    width: pinchBaseOffset.width + (pinchAnchorInContent.x - viewCenter.x) * deltaScale,
                    height: pinchBaseOffset.height + (pinchAnchorInContent.y - viewCenter.y) * deltaScale
                )
            }

            applyViewportTransform()
            layoutImageAndCursor()
        case .ended, .cancelled, .failed:
            if controller.viewportScale <= 1.01 {
                controller.viewportScale = 1
                controller.viewportOffset = .zero
                controller.viewportFocalContent = .zero
                controller.viewportFocalScreen = .zero
            }
            applyViewportTransform()
            layoutImageAndCursor()
        default:
            break
        }
    }

    @objc private func handleViewportPan(_ gesture: UIPanGestureRecognizer) {
        guard let controller, canPanViewport, !pointerIsIndirect else { return }
        switch gesture.state {
        case .began:
            panBaseOffset = controller.viewportOffset
        case .changed:
            let translation = gesture.translation(in: self)
            controller.viewportOffset = clampedViewportOffset(
                CGSize(
                    width: panBaseOffset.width + translation.x,
                    height: panBaseOffset.height + translation.y
                ),
                scale: controller.viewportScale
            )
            applyViewportTransform()
            layoutImageAndCursor()
        default:
            break
        }
    }

    @objc private func handleCursorMove(_ gesture: UILongPressGestureRecognizer) {
        guard mouseMode == .mousePointer, !canPanViewport, !pointerIsIndirect else { return }
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            lastCursorDragPoint = point
            controller?.sendTrackpadMove(translation: .zero, padSize: fitRect.size, isPanning: true)
        case .changed:
            let delta = CGPoint(x: point.x - lastCursorDragPoint.x, y: point.y - lastCursorDragPoint.y)
            controller?.sendTrackpadMove(translation: delta, padSize: fitRect.size, isPanning: true)
            lastCursorDragPoint = point
        case .ended, .cancelled, .failed:
            controller?.trackpadPanEnded()
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if pointerIsIndirect {
            mouseHandler.handleIndirectTap(at: gesture.location(in: self))
            return
        }
        switch mouseMode {
        case .directTouch:
            guard let mapped = mapTouchToDesktop(gesture.location(in: self)) else { return }
            controller?.sendClick(at: mapped, desktopSize: fitRect.size, button: .left)
        case .mousePointer:
            controller?.sendClickAtCursor(button: .left)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if pointerIsIndirect {
            let point = gesture.location(in: self)
            mouseHandler.handleIndirectTap(at: point)
            mouseHandler.handleIndirectTap(at: point)
            return
        }
        switch mouseMode {
        case .directTouch:
            guard let mapped = mapTouchToDesktop(gesture.location(in: self)) else { return }
            controller?.sendClick(at: mapped, desktopSize: fitRect.size, button: .left)
            controller?.sendClick(at: mapped, desktopSize: fitRect.size, button: .left)
        case .mousePointer:
            controller?.sendClickAtCursor(button: .left)
            controller?.sendClickAtCursor(button: .left)
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !pointerIsIndirect else { return }
        switch mouseMode {
        case .directTouch:
            guard let mapped = mapTouchToDesktop(gesture.location(in: self)) else { return }
            controller?.sendClick(at: mapped, desktopSize: fitRect.size, button: .right)
        case .mousePointer:
            controller?.sendClickAtCursor(button: .right)
        }
    }

    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        guard mouseMode == .mousePointer else { return }
        controller?.sendClickAtCursor(button: .right)
    }

    @objc private func handleTwoFingerScroll(_ gesture: UIPanGestureRecognizer) {
        guard gesture.numberOfTouches >= 2, gesture.state == .changed || gesture.state == .ended else { return }
        let delta = Int(-gesture.translation(in: self).y / 8)
        guard delta != 0 else { return }
        switch mouseMode {
        case .mousePointer:
            controller?.sendScrollAtCursor(deltaY: delta)
        case .directTouch:
            guard let mapped = mapTouchToDesktop(gesture.location(in: self)) else { return }
            controller?.sendScroll(deltaY: delta, at: mapped, desktopSize: fitRect.size)
        }
        gesture.setTranslation(.zero, in: self)
    }

    @objc private func handleMousePan(_ gesture: UIPanGestureRecognizer) {
        guard pointerIsIndirect else { return }
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began:
            mouseHandler.handleIndirectPanBegan(at: point)
        case .changed:
            mouseHandler.handleIndirectPanChanged(to: point)
        case .ended, .cancelled, .failed:
            mouseHandler.handleIndirectPanEnded()
        default:
            break
        }
    }

    private func mapTouchToDesktop(_ pointInSelf: CGPoint) -> CGPoint? {
        let point = screenToContent(pointInSelf)
        guard fitRect.width > 0, fitRect.height > 0 else { return nil }
        let clamped = CGPoint(
            x: min(max(point.x, fitRect.minX), fitRect.maxX),
            y: min(max(point.y, fitRect.minY), fitRect.maxY)
        )
        return CGPoint(x: clamped.x - fitRect.minX, y: clamped.y - fitRect.minY)
    }

    private var canPanViewport: Bool {
        (controller?.viewportScale ?? 1) > 1.01
    }

    /// 限制平移范围，避免把桌面拖出屏幕太远
    private func clampedViewportOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        guard scale > 1.001, fitRect.width > 0, fitRect.height > 0 else { return .zero }
        let maxX = fitRect.width * (scale - 1) * 0.6 + 48
        let maxY = fitRect.height * (scale - 1) * 0.6 + 48
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY)
        )
    }
}

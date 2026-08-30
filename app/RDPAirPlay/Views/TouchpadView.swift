import SwiftUI

/// F-AP-02 / F-IN-02：扩展模式下本机控制台（触控板 + 修饰键 + 功能键）
struct TouchpadView: View {
    @ObservedObject var controller: RDPSessionController
    @Binding var showKeyboard: Bool
    @Binding var useSystemKeyboard: Bool
    @State private var showFunctionKeys = true

    var body: some View {
        VStack(spacing: 8) {
            trackpadArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            clickButtons

            if showKeyboard {
                keyboardPanel
            } else {
                ModifierToggleBar(controller: controller)
                if showFunctionKeys {
                    FunctionKeyPad(controller: controller)
                }
                functionKeysFooter
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.2), value: showKeyboard)
    }

    @ViewBuilder
    private var keyboardPanel: some View {
        if useSystemKeyboard {
            WindowsAuxiliaryKeyboardView(controller: controller)
        } else {
            WindowsRemoteKeyboardPanel(controller: controller) {
                useSystemKeyboard = true
            }
        }
    }

    private var functionKeysFooter: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFunctionKeys.toggle()
                }
            } label: {
                Label(showFunctionKeys ? "收起功能键" : "功能键", systemImage: "function")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            Spacer()
            Text("单击左键 · 长按右键 · 双指滚动")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var trackpadArea: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(white: 0.11))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .overlay {
                        Canvas { context, size in
                            let step: CGFloat = 28
                            var x: CGFloat = step
                            while x < size.width {
                                var path = Path()
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                                context.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 1)
                                x += step
                            }
                            var y: CGFloat = step
                            while y < size.height {
                                var path = Path()
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                                context.stroke(path, with: .color(.white.opacity(0.03)), lineWidth: 1)
                                y += step
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .allowsHitTesting(false)
                    }

                VStack(spacing: 6) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 28, weight: .medium))
                    Text("触控板")
                        .font(.subheadline.weight(.semibold))
                    Text("滑动移动指针，点按当前位置")
                        .font(.caption2)
                }
                .foregroundStyle(.white.opacity(0.32))
                .allowsHitTesting(false)

                TouchpadInteractionView(controller: controller)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clickButtons: some View {
        HStack(spacing: 8) {
            HoldClickButton(title: "左键", button: .left, controller: controller)
            HoldClickButton(title: "右键", button: .right, controller: controller)
        }
        .frame(height: 42)
    }
}

private struct HoldClickButton: View {
    let title: String
    let button: RDPMouseEvent.Button
    @ObservedObject var controller: RDPSessionController
    @State private var pressed = false

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(pressed ? 0.28 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        controller.sendMouseButton(button, down: true)
                    }
                    .onEnded { _ in
                        guard pressed else { return }
                        pressed = false
                        controller.sendMouseButton(button, down: false)
                    }
            )
    }
}

struct TouchpadInteractionView: UIViewRepresentable {
    @ObservedObject var controller: RDPSessionController

    func makeUIView(context: Context) -> TouchpadInteractionUIView {
        let view = TouchpadInteractionUIView()
        view.controller = controller
        return view
    }

    func updateUIView(_ uiView: TouchpadInteractionUIView, context: Context) {
        uiView.controller = controller
    }
}

final class TouchpadInteractionUIView: UIView, UIGestureRecognizerDelegate {
    var controller: RDPSessionController?

    private let mouseHandler = MouseInputHandler()
    private var pointerIsIndirect = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        mouseHandler.attach(to: self)
        mouseHandler.desktopSizeProvider = { [weak self] in self?.bounds.size ?? .zero }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)

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

        let twoFingerPan = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        twoFingerPan.minimumNumberOfTouches = 2
        addGestureRecognizer(twoFingerPan)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleRightTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        addGestureRecognizer(twoFingerTap)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        pointerIsIndirect = touch.type == .indirectPointer
        if pointerIsIndirect, gestureRecognizer is UILongPressGestureRecognizer {
            return false
        }
        return mouseHandler.gestureRecognizer(gestureRecognizer, shouldReceive: touch)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.numberOfTouches == 1 else { return }
        let point = gesture.location(in: self)
        let translation = gesture.translation(in: self)

        if pointerIsIndirect {
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
            return
        }

        switch gesture.state {
        case .began, .changed:
            controller?.sendTrackpadMove(translation: translation, padSize: bounds.size, isPanning: true)
            gesture.setTranslation(.zero, in: self)
        case .ended, .cancelled, .failed:
            if translation != .zero {
                controller?.sendTrackpadMove(translation: translation, padSize: bounds.size, isPanning: true)
            }
            controller?.trackpadPanEnded()
            gesture.setTranslation(.zero, in: self)
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        if pointerIsIndirect {
            mouseHandler.handleIndirectTap(at: gesture.location(in: self))
            return
        }
        controller?.sendClickAtCursor(button: .left)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if pointerIsIndirect {
            let point = gesture.location(in: self)
            mouseHandler.handleIndirectTap(at: point)
            mouseHandler.handleIndirectTap(at: point)
            return
        }
        controller?.sendClickAtCursor(button: .left)
        controller?.sendClickAtCursor(button: .left)
    }

    @objc private func handleRightTap(_ gesture: UITapGestureRecognizer) {
        controller?.sendClickAtCursor(button: .right)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !pointerIsIndirect else { return }
        controller?.sendClickAtCursor(button: .right)
    }

    @objc private func handleScroll(_ gesture: UIPanGestureRecognizer) {
        let step = Int(-gesture.translation(in: self).y / 10)
        guard abs(step) >= 1 else { return }
        controller?.sendScrollAtCursor(deltaY: step)
        gesture.setTranslation(.zero, in: self)
    }
}

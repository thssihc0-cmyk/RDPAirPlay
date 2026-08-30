import Foundation
import Combine
import UIKit

/// 会话编排：连接生命周期、弱网降档、音频
@MainActor
final class RDPSessionController: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var lastError: RDPConnectionError?
    @Published var colorMode: ColorMode = .fullColor
    @Published var lockColorMode = false
    @Published private(set) var latestFrame: RDPFrame?
    @Published var viewportScale: CGFloat = 1.0
    @Published var viewportOffset: CGSize = .zero
    /// 鼠标指针模式下缩放焦点（桌面内容坐标 / 屏幕坐标）
    @Published var viewportFocalContent: CGPoint = .zero
    @Published var viewportFocalScreen: CGPoint = .zero
    @Published var mouseMode: RemoteMouseMode = .mousePointer
    @Published var activeModifiers: RDPSessionModifiers = []
    @Published var cursor: RDPCursor = .hidden
    var onCursor: ((RDPCursor) -> Void)?

    private var userMovedCursor = false
    private var trackpadPanActive = false
    private var remotePointer: CGPoint?

    /// 当前应投到第二屏的画面（已套色彩模式）
    var displayImage: UIImage? {
        guard let image = latestFrame?.image else { return nil }
        if colorMode == .fullColor { return image }
        guard let cg = image.cgImage,
              let processed = ColorModeProcessor.apply(colorMode, to: cg) else {
            return image
        }
        return UIImage(cgImage: processed)
    }

    var onDisplayImage: ((UIImage?) -> Void)?

    let audioManager = AudioSessionManager()
    let networkMonitor = NetworkQualityMonitor()

    private var host: HostProfile?
    private var session: RDPSessionHandling?
    private var password: String = ""

    func reportLocalError(_ message: String) {
        lastError = .invalidConfiguration(message)
        state = .disconnected(reason: message)
    }

    func connect(to host: HostProfile, password: String) async {
        self.host = host
        self.password = password
        colorMode = host.colorMode
        lockColorMode = host.lockColorMode
        state = .connecting
        lastError = nil

        let session = RDPSessionFactory.makeSession()
        session.delegate = self
        self.session = session

        do {
            try await audioManager.configureForRemoteDesktop(
                speaker: host.enableSpeaker,
                microphone: host.enableMicrophone
            )
            networkMonitor.start()

            let options = RDPConnectionOptions(
                hostname: host.hostname,
                port: host.port,
                username: host.username,
                password: password,
                width: host.effectiveWidth,
                height: host.effectiveHeight,
                enableNLA: true,
                enableSpeaker: host.enableSpeaker,
                enableMicrophone: host.enableMicrophone
            )
            try await session.connect(options: options)
        } catch let error as RDPConnectionError {
            await handleFailure(error)
        } catch {
            await handleFailure(.disconnected(error.localizedDescription))
        }
    }

    func disconnect() async {
        releaseHeldModifiers()
        userMovedCursor = false
        trackpadPanActive = false
        remotePointer = nil
        networkMonitor.stop()
        audioManager.deactivate()
        await session?.disconnect()
        session = nil
        state = .disconnected(reason: nil)
        latestFrame = nil
        cursor = .hidden
        onCursor?(.hidden)
    }

    func changeResolution(width: Int, height: Int) async {
        guard ResolutionPreset.validate(width: width, height: height) else {
            lastError = .invalidConfiguration("分辨率超出允许范围")
            return
        }
        do {
            try await session?.setResolution(width: width, height: height)
            host?.customWidth = width
            host?.customHeight = height
        } catch let error as RDPConnectionError {
            lastError = error
        } catch {
            lastError = .resolutionChangeFailed
        }
    }

    func setColorMode(_ mode: ColorMode, locked: Bool) {
        colorMode = mode
        lockColorMode = locked
    }

    func sendClick(at point: CGPoint, desktopSize: CGSize, button: RDPMouseEvent.Button) {
        guard let mapped = mapPoint(point, desktopSize: desktopSize) else { return }
        predictCursor(at: mapped)
        session?.sendMouse(RDPMouseEvent(x: mapped.x, y: mapped.y, button: button, action: .down))
        session?.sendMouse(RDPMouseEvent(x: mapped.x, y: mapped.y, button: button, action: .up))
    }

    func sendClickAtCursor(button: RDPMouseEvent.Button) {
        let point = activeRemotePointer()
        let x = Int(point.x)
        let y = Int(point.y)
        session?.sendMouse(RDPMouseEvent(x: x, y: y, button: button, action: .down))
        session?.sendMouse(RDPMouseEvent(x: x, y: y, button: button, action: .up))
    }

    func sendMouseMove(to point: CGPoint, desktopSize: CGSize) {
        guard let mapped = mapPoint(point, desktopSize: desktopSize) else { return }
        predictCursor(at: mapped)
        session?.sendMouse(RDPMouseEvent(x: mapped.x, y: mapped.y, button: .left, action: .move))
    }

    func sendTrackpadMove(translation: CGPoint, padSize: CGSize, isPanning: Bool) {
        trackpadPanActive = isPanning
        let desktop = desktopSize
        let scaleX = desktop.width / max(padSize.width, 1)
        let scaleY = desktop.height / max(padSize.height, 1)
        let base = activeRemotePointer(in: desktop)
        var x = base.x + translation.x * scaleX
        var y = base.y + translation.y * scaleY
        x = min(max(x, 0), desktop.width - 1)
        y = min(max(y, 0), desktop.height - 1)
        let mapped = (x: Int(x), y: Int(y))
        applyLocalPointer(mapped)
        session?.sendMouse(RDPMouseEvent(x: mapped.x, y: mapped.y, button: .left, action: .move))
    }

    func trackpadPanEnded() {
        trackpadPanActive = false
    }

    func sendKeyTap(_ code: UInt16) {
        sendKeyCode(code, action: .down)
        sendKeyCode(code, action: .up)
    }

    func sendMouseButton(_ button: RDPMouseEvent.Button, down: Bool) {
        let point = activeRemotePointer()
        session?.sendMouse(RDPMouseEvent(x: Int(point.x), y: Int(point.y), button: button, action: down ? .down : .up))
    }

    func sendScrollAtCursor(deltaY: Int) {
        guard deltaY != 0 else { return }
        let point = activeRemotePointer()
        session?.sendMouse(RDPMouseEvent(x: Int(point.x), y: Int(point.y), button: .left, action: .scroll(deltaX: 0, deltaY: deltaY)))
    }

    func sendCtrlAltDelete() {
        let hadCtrl = activeModifiers.contains(.ctrl)
        let hadAlt = activeModifiers.contains(.alt)
        if !hadCtrl { sendKeyCode(RDPScanCode.lControl, action: .down) }
        if !hadAlt { sendKeyCode(RDPScanCode.lAlt, action: .down) }
        sendKeyTap(RDPScanCode.delete)
        if !hadAlt { sendKeyCode(RDPScanCode.lAlt, action: .up) }
        if !hadCtrl { sendKeyCode(RDPScanCode.lControl, action: .up) }
    }

    func releaseHeldModifiers() {
        for modifier in [RDPSessionModifiers.ctrl, .alt, .shift, .win] where activeModifiers.contains(modifier) {
            sendKeyCode(modifier.scanCode, action: .up)
        }
        activeModifiers = []
    }

    private func predictCursor(at mapped: (x: Int, y: Int)) {
        applyLocalPointer(mapped)
    }

    private func applyLocalPointer(_ mapped: (x: Int, y: Int)) {
        userMovedCursor = true
        let point = CGPoint(x: mapped.x, y: mapped.y)
        remotePointer = point
        var next = cursor
        next.position = point
        next.visible = true
        if next.image == nil {
            next = .defaultArrow(at: point)
        }
        cursor = next
        onCursor?(next)
    }

    private func activeRemotePointer(in desktop: CGSize? = nil) -> CGPoint {
        if let remotePointer {
            return remotePointer
        }
        if cursor.visible {
            return cursor.position
        }
        let size = desktop ?? desktopSize
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }

    private func shouldApplyServerCursorPosition(_ incoming: RDPCursor) -> Bool {
        if incoming.updatesImageOnly {
            return false
        }
        if trackpadPanActive || userMovedCursor {
            return false
        }
        if incoming.position == .zero && cursor.position != .zero {
            return false
        }
        return true
    }

    func sendScroll(deltaY: Int, at point: CGPoint, desktopSize: CGSize) {
        guard let mapped = mapPoint(point, desktopSize: desktopSize) else { return }
        session?.sendMouse(RDPMouseEvent(x: mapped.x, y: mapped.y, button: .left, action: .scroll(deltaX: 0, deltaY: deltaY)))
    }

    func sendKeyCode(_ code: UInt16, action: RDPKeyEvent.Action) {
        session?.sendKey(RDPKeyEvent(keyCode: code, action: action, modifiers: activeModifiers))
    }

    func sendHardwareKey(_ code: UInt16, action: RDPKeyEvent.Action) {
        session?.sendKey(RDPKeyEvent(keyCode: code, action: action, modifiers: []))
    }

    func sendText(_ text: String) {
        session?.sendUnicodeText(text)
    }

    func toggleModifier(_ modifier: RDPSessionModifiers) {
        let turningOn = !activeModifiers.contains(modifier)
        if turningOn {
            activeModifiers.insert(modifier)
            sendKeyCode(modifier.scanCode, action: .down)
        } else {
            activeModifiers.remove(modifier)
            sendKeyCode(modifier.scanCode, action: .up)
        }
    }

    private var desktopSize: CGSize {
        if let frame = latestFrame {
            return CGSize(width: max(frame.width, 1), height: max(frame.height, 1))
        }
        return CGSize(width: host?.effectiveWidth ?? 1920, height: host?.effectiveHeight ?? 1080)
    }

    private func mapPoint(_ point: CGPoint, desktopSize: CGSize) -> (x: Int, y: Int)? {
        guard desktopSize.width > 0, desktopSize.height > 0 else { return nil }
        let x = Int((point.x / desktopSize.width) * CGFloat(host?.effectiveWidth ?? Int(desktopSize.width)))
        let y = Int((point.y / desktopSize.height) * CGFloat(host?.effectiveHeight ?? Int(desktopSize.height)))
        return (max(0, x), max(0, y))
    }

    private func handleFailure(_ error: RDPConnectionError) async {
        lastError = error
        state = .disconnected(reason: error.errorDescription)
        releaseHeldModifiers()
        networkMonitor.stop()
        audioManager.deactivate()
        await session?.disconnect()
        session = nil
    }

    private func applyAdaptiveColorModeIfNeeded() {
        let suggested = networkMonitor.suggestedColorMode(current: colorMode, locked: lockColorMode)
        if suggested != colorMode {
            colorMode = suggested
        }
    }
}

extension RDPSessionController: RDPSessionDelegate {
    nonisolated func sessionDidConnect() {
        Task { @MainActor in
            state = .connected
            lastError = nil
            if cursor.image == nil {
                cursor = .defaultArrow(at: CGPoint(x: 64, y: 64))
                onCursor?(cursor)
            }
        }
    }

    nonisolated func sessionDidDisconnect(error: RDPConnectionError?) {
        Task { @MainActor in
            state = .disconnected(reason: error?.errorDescription)
            lastError = error
            networkMonitor.stop()
            audioManager.deactivate()
        }
    }

    nonisolated func sessionDidReceiveFrame(_ frame: RDPFrame) {
        Task { @MainActor in
            latestFrame = frame
            onDisplayImage?(displayImage)
        }
    }

    nonisolated func sessionDidReceiveCursor(_ incoming: RDPCursor) {
        Task { @MainActor in
            var next = cursor
            if incoming.updatesImageOnly {
                if let image = incoming.image {
                    next.image = image
                    next.hotspot = incoming.hotspot
                }
            } else if shouldApplyServerCursorPosition(incoming) {
                next.position = incoming.position
                remotePointer = incoming.position
            }
            next.visible = incoming.visible
            if next.image == nil && incoming.visible {
                next = .defaultArrow(at: next.position)
            }
            cursor = next
            onCursor?(next)
        }
    }

    nonisolated func sessionDidUpdateMetrics(rttMs: Double, lossPercent: Double, kbps: Int) {
        Task { @MainActor in
            networkMonitor.report(rttMs: rttMs, lossPercent: lossPercent, kbps: kbps)
            applyAdaptiveColorModeIfNeeded()
        }
    }
}

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
    /// 仅供调试/镜像预览；不 @Published，避免打字时整页 SwiftUI 重绘
    private(set) var latestFrame: RDPFrame?
    @Published var viewportScale: CGFloat = 1.0
    @Published var viewportOffset: CGSize = .zero
    /// 鼠标指针模式下缩放焦点（桌面内容坐标 / 屏幕坐标）
    @Published var viewportFocalContent: CGPoint = .zero
    @Published var viewportFocalScreen: CGPoint = .zero
    /// 画布在下一帧以光标为锚点应用该缩放（顶部放大镜）
    @Published var pendingZoomScale: CGFloat?
    @Published var mouseMode: RemoteMouseMode = .mousePointer
    @Published var activeModifiers: RDPSessionModifiers = []
    /// 已启用 RDP 速度优先（关闭远程壁纸/动画/拖动阴影）
    @Published private(set) var isSpeedOptimized = false
    private(set) var cursor: RDPCursor = .hidden
    var onCursor: ((RDPCursor) -> Void)?

    private var userMovedCursor = false
    private var trackpadPanActive = false
    private var remotePointer: CGPoint?

    var isViewportZoomed: Bool { viewportScale > 1.01 }

    /// 顶部放大镜：在光标处 1× ↔ 2× 切换
    func toggleViewportZoom() {
        if isViewportZoomed {
            viewportScale = 1
            viewportOffset = .zero
            viewportFocalContent = .zero
            viewportFocalScreen = .zero
            pendingZoomScale = nil
        } else {
            pendingZoomScale = 2
        }
    }

    /// 当前应投到第二屏的画面（已套色彩模式）
    func displayImage(for frame: RDPFrame?) -> UIImage? {
        guard let image = frame?.image else { return nil }
        if colorMode == .fullColor { return image }
        guard let cg = image.cgImage,
              let processed = ColorModeProcessor.apply(colorMode, to: cg) else {
            return image
        }
        return UIImage(cgImage: processed)
    }

    var displayImage: UIImage? {
        displayImage(for: latestFrame)
    }

    var onDisplayImage: ((UIImage?) -> Void)?

    let audioManager = AudioSessionManager()
    let networkMonitor = NetworkQualityMonitor()

    private var host: HostProfile?
    private var session: RDPSessionHandling?
    private var password: String = ""
    private var desktopWidth = 1920
    private var desktopHeight = 1080
    private var lastDisplayPresentTime: CFTimeInterval = 0
    private let minDisplayInterval: CFTimeInterval = 1.0 / 20.0
    private var pendingPresentScheduled = false

    /// 合并高频帧/光标回调，避免打字时主线程 Task 堆积导致卡死被系统杀进程
    private let uiUpdateBuffer = UIUpdateCoalesceBuffer()
    private var bandwidthEstimator = FrameBandwidthEstimator()
    private var speedOptimizationReconnectPending = false

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
        ScreenWakeLock.acquire()

        let session = RDPSessionFactory.makeSession()
        session.delegate = self
        self.session = session

        do {
            if host.enableMicrophone {
                let granted = await audioManager.requestMicrophoneAccessIfNeeded()
                guard granted else {
                    self.session = nil
                    ScreenWakeLock.release()
                    reportLocalError("未获得麦克风权限，请在「设置 → RDP AirPlay → 麦克风」中允许访问。")
                    return
                }
            }
            try await audioManager.configureForRemoteDesktop(
                speaker: host.enableSpeaker,
                microphone: host.enableMicrophone
            )
            networkMonitor.start()
            bandwidthEstimator.reset()

            let optimizeForSpeed = NetworkPathObserver.shared.prefersSpeedOptimization
            try await openSession(
                host: host,
                password: password,
                optimizeForSpeed: optimizeForSpeed
            )
            desktopWidth = host.effectiveWidth
            desktopHeight = host.effectiveHeight
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
        bandwidthEstimator.reset()
        isSpeedOptimized = false
        speedOptimizationReconnectPending = false
        audioManager.deactivate()
        await session?.disconnect()
        session = nil
        state = .disconnected(reason: nil)
        latestFrame = nil
        cursor = .hidden
        onCursor?(.hidden)
        ScreenWakeLock.release()
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
        if desktopWidth > 0, desktopHeight > 0 {
            return CGSize(width: desktopWidth, height: desktopHeight)
        }
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
        bandwidthEstimator.reset()
        isSpeedOptimized = false
        speedOptimizationReconnectPending = false
        audioManager.deactivate()
        await session?.disconnect()
        session = nil
        ScreenWakeLock.release()
    }

    private func applyAdaptiveColorModeIfNeeded() {
        let suggested = networkMonitor.suggestedColorMode(current: colorMode, locked: lockColorMode)
        if suggested != colorMode {
            colorMode = suggested
        }
    }

    private func openSession(host: HostProfile, password: String, optimizeForSpeed: Bool) async throws {
        let options = RDPConnectionOptions(
            hostname: host.hostname,
            port: host.port,
            username: host.username,
            password: password,
            width: host.effectiveWidth,
            height: host.effectiveHeight,
            enableNLA: true,
            enableSpeaker: host.enableSpeaker,
            enableMicrophone: host.enableMicrophone,
            optimizeForSpeed: optimizeForSpeed
        )
        try await session?.connect(options: options)
        isSpeedOptimized = optimizeForSpeed
    }

    /// 会话中弱网持续恶化时，重连以应用 RDP 性能标志（壁纸/动画等仅在连接时协商）
    private func applyAdaptivePerformanceIfNeeded() async {
        guard case .connected = state else { return }
        guard !isSpeedOptimized else { return }
        guard !speedOptimizationReconnectPending else { return }
        guard networkMonitor.shouldEnableSpeedOptimization else { return }
        guard networkMonitor.consecutiveLowSamples >= 2 else { return }
        guard let host else { return }

        speedOptimizationReconnectPending = true
        releaseHeldModifiers()
        await session?.disconnect()
        session = nil

        let newSession = RDPSessionFactory.makeSession()
        newSession.delegate = self
        session = newSession
        state = .connecting

        do {
            try await openSession(host: host, password: password, optimizeForSpeed: true)
        } catch let error as RDPConnectionError {
            speedOptimizationReconnectPending = false
            await handleFailure(error)
        } catch {
            speedOptimizationReconnectPending = false
            await handleFailure(.disconnected(error.localizedDescription))
        }
    }

    private func recordFrameMetrics(_ frame: RDPFrame) {
        guard let metrics = bandwidthEstimator.recordFrame(width: frame.width, height: frame.height) else {
            return
        }
        networkMonitor.report(rttMs: metrics.rttMs, lossPercent: 0, kbps: metrics.kbps)
        applyAdaptiveColorModeIfNeeded()
        Task { await applyAdaptivePerformanceIfNeeded() }
    }
}

extension RDPSessionController: RDPSessionDelegate {
    nonisolated func sessionDidConnect() {
        Task { @MainActor in
            speedOptimizationReconnectPending = false
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
            ScreenWakeLock.release()
        }
    }

    nonisolated func sessionDidReceiveFrame(_ frame: RDPFrame) {
        let schedule = uiUpdateBuffer.enqueueFrame(frame)
        guard schedule else { return }
        Task { @MainActor in
            flushPendingFrame()
        }
    }

    nonisolated func sessionDidReceiveCursor(_ incoming: RDPCursor) {
        let schedule = uiUpdateBuffer.enqueueCursor(incoming)
        guard schedule else { return }
        Task { @MainActor in
            flushPendingCursor()
        }
    }

    @MainActor
    private func flushPendingFrame() {
        guard let frame = uiUpdateBuffer.takeFrame() else { return }
        latestFrame = frame
        desktopWidth = frame.width
        desktopHeight = frame.height
        recordFrameMetrics(frame)
        presentThrottledFrame()
    }

    @MainActor
    private func presentThrottledFrame() {
        let now = CACurrentMediaTime()
        if now - lastDisplayPresentTime >= minDisplayInterval {
            lastDisplayPresentTime = now
            pendingPresentScheduled = false
            onDisplayImage?(displayImage(for: latestFrame))
            return
        }
        guard !pendingPresentScheduled else { return }
        pendingPresentScheduled = true
        let delay = minDisplayInterval - (now - lastDisplayPresentTime)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0.001) * 1_000_000_000))
            pendingPresentScheduled = false
            presentThrottledFrame()
        }
    }

    @MainActor
    private func flushPendingCursor() {
        guard let incoming = uiUpdateBuffer.takeCursor() else { return }

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

    nonisolated func sessionDidUpdateMetrics(rttMs: Double, lossPercent: Double, kbps: Int) {
        Task { @MainActor in
            networkMonitor.report(rttMs: rttMs, lossPercent: lossPercent, kbps: kbps)
            applyAdaptiveColorModeIfNeeded()
            await applyAdaptivePerformanceIfNeeded()
        }
    }
}

/// 线程安全的帧/光标合并缓冲：只保留最新一帧，避免主线程 Task 风暴
private final class UIUpdateCoalesceBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingFrame: RDPFrame?
    private var frameFlushScheduled = false
    private var pendingCursor: RDPCursor?
    private var cursorFlushScheduled = false

    func enqueueFrame(_ frame: RDPFrame) -> Bool {
        lock.lock()
        pendingFrame = frame
        let schedule = !frameFlushScheduled
        if schedule { frameFlushScheduled = true }
        lock.unlock()
        return schedule
    }

    func takeFrame() -> RDPFrame? {
        lock.lock()
        let frame = pendingFrame
        pendingFrame = nil
        frameFlushScheduled = false
        lock.unlock()
        return frame
    }

    func enqueueCursor(_ cursor: RDPCursor) -> Bool {
        lock.lock()
        pendingCursor = cursor
        let schedule = !cursorFlushScheduled
        if schedule { cursorFlushScheduled = true }
        lock.unlock()
        return schedule
    }

    func takeCursor() -> RDPCursor? {
        lock.lock()
        let cursor = pendingCursor
        pendingCursor = nil
        cursorFlushScheduled = false
        lock.unlock()
        return cursor
    }
}

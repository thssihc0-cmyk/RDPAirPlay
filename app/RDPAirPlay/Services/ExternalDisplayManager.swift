import SwiftUI
import UIKit

/// F-AP-01 ~ F-AP-04: AirPlay / 外接屏管理
enum ExternalDisplayMode: String, CaseIterable, Identifiable {
    case extended
    case mirror

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .extended: return "扩展（电视显示桌面）"
        case .mirror: return "镜像（与本机相同）"
        }
    }
}

enum ExternalDisplayKind: String {
    case none
    /// AirPlay 已开，等待系统分配独立外接 Scene（挂上窗口后电视才显示桌面）
    case airplayPending
    case dedicated
    /// 仅当用户主动选镜像时使用
    case mirrored
}

/// 第二屏用 UIKit 刷帧，避免 SwiftUI 在外接 Scene 上不刷新。
final class ExternalDesktopViewController: UIViewController {
    let imageView = UIImageView()
    let cursorView = UIImageView()
    private let placeholder = UILabel()
    private var desktopSize = CGSize.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.frame = view.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(imageView)

        cursorView.contentMode = .topLeft
        cursorView.backgroundColor = .clear
        cursorView.isOpaque = false
        cursorView.isUserInteractionEnabled = false
        view.addSubview(cursorView)

        placeholder.text = "等待远程桌面…"
        placeholder.textColor = UIColor(white: 1, alpha: 0.55)
        placeholder.font = .preferredFont(forTextStyle: .title2)
        placeholder.textAlignment = .center
        placeholder.frame = view.bounds
        placeholder.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(placeholder)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let image = imageView.image {
            setCursor(lastCursor)
            _ = image
        }
    }

    private var lastCursor: RDPCursor = .hidden

    func setImage(_ image: UIImage?) {
        imageView.image = image
        if let image {
            desktopSize = image.size
        }
        placeholder.isHidden = image != nil
    }

    func setCursor(_ cursor: RDPCursor) {
        lastCursor = cursor
        let image = cursor.image ?? RDPCursor.arrowImage
        cursorView.image = image
        cursorView.isHidden = !cursor.visible
        guard cursor.visible, desktopSize.width > 1, desktopSize.height > 1 else { return }

        let bounds = view.bounds
        let scale = min(bounds.width / desktopSize.width, bounds.height / desktopSize.height)
        let drawSize = CGSize(width: desktopSize.width * scale, height: desktopSize.height * scale)
        let origin = CGPoint(x: (bounds.width - drawSize.width) / 2, y: (bounds.height - drawSize.height) / 2)
        let cursorSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        cursorView.frame = CGRect(
            x: origin.x + (cursor.position.x - cursor.hotspot.x) * scale,
            y: origin.y + (cursor.position.y - cursor.hotspot.y) * scale,
            width: cursorSize.width,
            height: cursorSize.height
        )
        view.bringSubviewToFront(cursorView)
    }
}

@MainActor
final class ExternalDisplayManager: ObservableObject {
    private static weak var sharedInstance: ExternalDisplayManager?

    static func shared() -> ExternalDisplayManager? { sharedInstance }

    static func makePlaceholderController() -> UIViewController {
        let controller = ExternalDesktopViewController()
        return controller
    }

    @Published private(set) var isExternalConnected = false
    @Published private(set) var kind: ExternalDisplayKind = .none
    @Published private(set) var isExternalWindowReady = false
    @Published private(set) var hasPresentedFrame = false
    @Published private(set) var detectionSummary = "未连接"
    @Published var preferredMode: ExternalDisplayMode = .extended
    @Published var pendingModeChoice = false

    private var sessionActive = false
    private var lastImage: UIImage?
    private var lastCursor: RDPCursor = .hidden
    private var externalScene: UIWindowScene?
    private var externalScreen: UIScreen?
    private var externalWindow: UIWindow?
    private var surface: ExternalDesktopViewController?
    private var boundsRetryTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?

    /// 电视窗口就绪且选了扩展模式，本机切触控板（不要求已刷帧，电视可先显示占位）
    var useExtendedLayout: Bool {
        kind == .dedicated && preferredMode == .extended && isExternalWindowReady
    }

    var statusCaption: String {
        if hasPresentedFrame && isExternalWindowReady {
            return "电视已显示远程桌面"
        }
        switch kind {
        case .none:
            return detectionSummary
        case .airplayPending:
            return "AirPlay 已连接，正在把画面切到电视…"
        case .mirrored:
            return "镜像模式：手机与电视显示相同画面"
        case .dedicated:
            return isExternalWindowReady ? "第二屏已就绪，等待画面" : "外接屏已连接，正在挂载窗口…"
        }
    }

    /// 扩展模式：独立 Scene 已就绪，或 AirPlay 中等待 Scene（目标始终是电视独显）
    var canUseExtendedMode: Bool {
        kind == .dedicated || kind == .airplayPending
    }

    init() {
        Self.sharedInstance = self
        refreshDisplays()
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleSceneChange), name: UIScene.willConnectNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSceneChange), name: UIScene.didActivateNotification, object: nil)
        center.addObserver(self, selector: #selector(handleSceneChange), name: .externalDisplaySceneDidConnect, object: nil)
        center.addObserver(self, selector: #selector(handleSceneDisconnect), name: UIScene.didDisconnectNotification, object: nil)
        center.addObserver(self, selector: #selector(handleScreenConnect), name: UIScreen.didConnectNotification, object: nil)
        center.addObserver(self, selector: #selector(handleScreenDisconnect), name: UIScreen.didDisconnectNotification, object: nil)
        center.addObserver(self, selector: #selector(handleScreenModeChange), name: UIScreen.modeDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(handleAppDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pollTask?.cancel()
    }

    func integrateExternalScene(_ scene: UIWindowScene, window: UIWindow) {
        externalScene = scene
        externalWindow = window
        externalScreen = scene.screen
        kind = .dedicated
        isExternalConnected = true
        configure(screen: scene.screen)
        detectionSummary = "电视扩展屏已接管"
        preferredMode = .extended
        pendingModeChoice = false
        updateExternalWindowIfNeeded()
        if let lastImage {
            presentDesktopImage(lastImage)
        }
        presentCursor(lastCursor)
    }

    func externalSceneDidDisconnect(_ scene: UIWindowScene) {
        guard externalScene === scene else { return }
        refreshDisplays()
    }

    func beginSessionOutput() {
        sessionActive = true
        preferredMode = .extended
        startPolling()
        refreshDisplays()
        updateExternalWindowIfNeeded()
        if let lastImage {
            presentDesktopImage(lastImage)
        }
        presentCursor(lastCursor)
    }

    func refreshConnection() {
        refreshDisplays()
        if sessionActive {
            updateExternalWindowIfNeeded()
            if let lastImage {
                presentDesktopImage(lastImage)
            }
            presentCursor(lastCursor)
        }
    }

    func endSessionOutput() {
        sessionActive = false
        pollTask?.cancel()
        pollTask = nil
        lastImage = nil
        lastCursor = .hidden
        hasPresentedFrame = false
        boundsRetryTask?.cancel()
        tearDownExternalWindow(keepSystemWindow: true)
    }

    func presentDesktopImage(_ image: UIImage?) {
        lastImage = image
        surface?.setImage(image)
        if image != nil, isExternalWindowReady {
            hasPresentedFrame = true
        }
    }

    func presentCursor(_ cursor: RDPCursor) {
        lastCursor = cursor
        surface?.setCursor(cursor)
    }

    func applyMode(_ mode: ExternalDisplayMode) {
        preferredMode = mode
        pendingModeChoice = false
        updateExternalWindowIfNeeded()
        if let lastImage {
            presentDesktopImage(lastImage)
        }
        presentCursor(lastCursor)
    }

    @objc private func handleSceneChange(_ notification: Notification) {
        Task { @MainActor in
            refreshDisplays()
        }
    }

    @objc private func handleSceneDisconnect(_ notification: Notification) {
        Task { @MainActor in
            refreshDisplays()
            if kind != .dedicated {
                pendingModeChoice = false
            }
        }
    }

    @objc private func handleScreenConnect(_ notification: Notification) {
        Task { @MainActor in
            refreshDisplays()
        }
    }

    @objc private func handleScreenDisconnect(_ notification: Notification) {
        Task { @MainActor in
            refreshDisplays()
            pendingModeChoice = false
        }
    }

    @objc private func handleScreenModeChange(_ notification: Notification) {
        Task { @MainActor in
            refreshDisplays()
            if let lastImage {
                presentDesktopImage(lastImage)
            }
        }
    }

    @objc private func handleAppDidBecomeActive(_ notification: Notification) {
        Task { @MainActor in
            refreshDisplays()
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                let interval: UInt64 = (kind == .airplayPending) ? 500_000_000 : 2_000_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled, sessionActive else { break }
                refreshDisplays()
            }
        }
    }

    private func refreshDisplays() {
        boundsRetryTask?.cancel()

        // 独立外接 Scene 优先：挂上 UIWindow 后电视显示 App 内容（替代镜像）
        if let scene = firstExternalWindowScene() {
            applyDedicated(scene: scene, screen: scene.screen)
            logDetection()
            return
        }

        let extras = UIScreen.screens.filter { $0 != UIScreen.main }
        if let screen = extras.last {
            externalScene = windowScene(for: screen)
            externalScreen = screen
            isExternalConnected = true
            configure(screen: screen)
            kind = .dedicated
            preferredMode = .extended
            detectionSummary = "检测到独立外接屏"
            updateExternalWindowIfNeeded()
            logDetection()
            return
        }

        if isAirPlayCaptured() {
            isExternalConnected = true
            externalScene = nil
            externalScreen = nil
            if preferredMode == .mirror {
                kind = .mirrored
                detectionSummary = "镜像模式"
                tearDownExternalWindow(keepSystemWindow: true)
            } else {
                kind = .airplayPending
                preferredMode = .extended
                detectionSummary = "AirPlay 已连接，等待扩展屏 Scene"
                updateExternalWindowIfNeeded()
            }
            logDetection()
            return
        }

        kind = .none
        externalScene = nil
        externalScreen = nil
        isExternalConnected = false
        hasPresentedFrame = false
        isExternalWindowReady = false
        detectionSummary = "未连接电视"
        tearDownExternalWindow(keepSystemWindow: false)
        logDetection()
    }

    private func applyDedicated(scene: UIWindowScene, screen: UIScreen) {
        kind = .dedicated
        externalScene = scene
        externalScreen = screen
        isExternalConnected = true
        preferredMode = .extended
        pendingModeChoice = false
        detectionSummary = "电视扩展屏已就绪"
        configure(screen: screen)
        updateExternalWindowIfNeeded()
    }

    private func isAirPlayCaptured() -> Bool {
        if UIScreen.main.isCaptured { return true }
        if #available(iOS 17.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .contains { $0.traitCollection.sceneCaptureState == .active }
        }
        return false
    }

    private func isMirrored(_ screen: UIScreen) -> Bool {
        if screen.mirrored != nil { return true }
        if UIScreen.main.mirrored == screen { return true }
        return false
    }

    private func configure(screen: UIScreen) {
        screen.overscanCompensation = .none
    }

    private func firstExternalWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let roleMatch = scenes.first(where: { isExternalDisplayRole($0.session.role) }) {
            return roleMatch
        }
        return scenes.first { $0.screen != UIScreen.main }
    }

    private func isExternalDisplayRole(_ role: UISceneSession.Role) -> Bool {
        if role == .windowExternalDisplayNonInteractive { return true }
        return role.rawValue.contains("ExternalDisplay")
    }

    private func windowScene(for screen: UIScreen) -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.screen == screen }
    }

    private func updateExternalWindowIfNeeded() {
        guard sessionActive, preferredMode == .extended else {
            tearDownExternalWindow(keepSystemWindow: true)
            return
        }

        if let scene = externalScene ?? firstExternalWindowScene() {
            attachWindow(to: scene)
            return
        }

        if let screen = externalScreen {
            attachWindowLegacy(to: screen)
            return
        }

        tearDownExternalWindow(keepSystemWindow: true)
    }

    private func attachWindow(to scene: UIWindowScene) {
        let bounds = scene.coordinateSpace.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            isExternalWindowReady = false
            scheduleBoundsRetry()
            return
        }

        let controller = surface ?? ExternalDesktopViewController()
        surface = controller
        controller.setImage(lastImage)
        controller.setCursor(lastCursor)

        let window: UIWindow
        if let existing = externalWindow, existing.windowScene === scene {
            window = existing
        } else if let existing = scene.windows.first(where: { $0.rootViewController != nil }) {
            window = existing
            externalWindow = existing
        } else {
            window = UIWindow(windowScene: scene)
            window.backgroundColor = .black
            externalWindow = window
        }

        window.frame = bounds
        window.rootViewController = controller
        window.windowLevel = .normal + 1
        window.isHidden = false
        isExternalWindowReady = true
        if lastImage != nil {
            hasPresentedFrame = true
        }
    }

    private func attachWindowLegacy(to screen: UIScreen) {
        let bounds = screen.bounds
        guard bounds.width > 1, bounds.height > 1 else {
            isExternalWindowReady = false
            scheduleBoundsRetry()
            return
        }

        if let scene = windowScene(for: screen) {
            attachWindow(to: scene)
            return
        }

        let controller = surface ?? ExternalDesktopViewController()
        surface = controller
        controller.setImage(lastImage)
        controller.setCursor(lastCursor)

        let window: UIWindow
        if let existing = externalWindow, existing.screen == screen {
            window = existing
        } else {
            window = UIWindow(frame: bounds)
            window.backgroundColor = .black
            externalWindow = window
        }

        window.screen = screen
        window.frame = bounds
        window.rootViewController = controller
        window.windowLevel = .normal + 1
        window.isHidden = false

        let attached = window.screen == screen && window.bounds.width > 1
        isExternalWindowReady = attached
        if attached, lastImage != nil {
            hasPresentedFrame = true
        }
        if !attached {
            scheduleBoundsRetry()
        }
    }

    private func scheduleBoundsRetry() {
        boundsRetryTask?.cancel()
        boundsRetryTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            refreshDisplays()
        }
    }

    /// keepSystemWindow: 保留 SceneDelegate 创建的窗口，避免系统收回外接 Scene
    private func tearDownExternalWindow(keepSystemWindow: Bool) {
        boundsRetryTask?.cancel()
        if keepSystemWindow {
            surface = nil
            isExternalWindowReady = false
            if let window = externalWindow, let placeholder = window.rootViewController as? ExternalDesktopViewController {
                placeholder.setImage(nil)
            }
            return
        }
        externalWindow?.isHidden = true
        externalWindow?.rootViewController = nil
        externalWindow = nil
        surface = nil
        isExternalWindowReady = false
    }

    private func logDetection() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let roles = scenes.map { $0.session.role.rawValue }.joined(separator: ", ")
        let screens = UIScreen.screens.count
        let captured = isAirPlayCaptured()
        print("[ExternalDisplay] kind=\(kind.rawValue) connected=\(isExternalConnected) ready=\(isExternalWindowReady) scenes=\(scenes.count) screens=\(screens) captured=\(captured) roles=[\(roles)]")
    }
}

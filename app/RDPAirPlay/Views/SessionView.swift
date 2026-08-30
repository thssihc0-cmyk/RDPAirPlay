import SwiftUI

/// F-CONN-04 / F-DISP-* / F-IN-*: 远程会话主界面
struct SessionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: HostStore
    @EnvironmentObject private var externalDisplay: ExternalDisplayManager

    let host: HostProfile

    @StateObject private var controller = RDPSessionController()
    @State private var showKeyboard = false
    @State private var showSettings = false
    @State private var resolutionWidth = ""
    @State private var resolutionHeight = ""

    @State private var showErrorAlert = false
    @State private var useSystemKeyboard = false
    @State private var showAirPlayMenu = false
    @StateObject private var orientationManager = SessionOrientationManager.shared
    @StateObject private var inputCoordinator = SessionInputCoordinator()

    var body: some View {
        NavigationStack {
            sessionRoot
        }
    }

    private var sessionRoot: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                if externalDisplay.useExtendedLayout {
                    extendedSessionLayout
                } else {
                    SecondScreenGuideView(
                        controller: controller,
                        externalDisplay: externalDisplay,
                        onRefresh: { externalDisplay.refreshConnection() },
                        onDisconnect: { Task { await disconnectAndDismiss() } }
                    )
                }

                SessionInputHosts(
                    coordinator: inputCoordinator,
                    showKeyboard: $showKeyboard,
                    useSystemKeyboard: $useSystemKeyboard
                )
                .equatable()

                SessionExternalDisplayHost()
                    .frame(width: 0, height: 0)

                if externalDisplay.useExtendedLayout {
                    SessionToolbar(
                        controller: controller,
                        externalDisplay: externalDisplay,
                        showKeyboard: $showKeyboard,
                        showAirPlayMenu: $showAirPlayMenu,
                        showSettings: $showSettings,
                        orientationManager: orientationManager,
                        onDisconnect: { Task { await disconnectAndDismiss() } }
                    )
                }
            }
            .onChange(of: showKeyboard) { isOpen in
                if !isOpen {
                    useSystemKeyboard = false
                }
            }
        }
        .navigationBarHidden(true)
        .task {
            await connect()
        }
        .onAppear {
            orientationManager.apply()
            inputCoordinator.attach(to: controller)
            externalDisplay.beginSessionOutput()
            controller.onDisplayImage = { image in
                externalDisplay.presentDesktopImage(image)
            }
            controller.onCursor = { cursor in
                externalDisplay.presentCursor(cursor)
            }
            externalDisplay.presentDesktopImage(controller.displayImage)
            externalDisplay.presentCursor(controller.cursor)
        }
        .onDisappear {
            controller.onDisplayImage = nil
            controller.onCursor = nil
            externalDisplay.endSessionOutput()
            orientationManager.reset()
            ScreenWakeLock.reset()
        }
        .confirmationDialog(
            "电视扩展屏",
            isPresented: $showAirPlayMenu,
            titleVisibility: .visible
        ) {
            airPlayDialogActions
        } message: {
            Text(airPlayDialogMessage)
        }
        .alert("连接失败", isPresented: $showErrorAlert) {
            Button("返回") { Task { await disconnectAndDismiss() } }
        } message: {
            Text(controller.lastError?.errorDescription ?? "未知错误")
        }
        .onChange(of: controller.lastError) { error in
            showErrorAlert = error != nil && !controller.state.isActive
        }
        .onChange(of: controller.colorMode) { _ in
            externalDisplay.presentDesktopImage(controller.displayImage)
        }
        .sheet(isPresented: $showSettings) {
            sessionSettingsSheet
        }
    }

    private var extendedSessionLayout: some View {
        VStack(spacing: 0) {
            SessionConnectionBar(
                controller: controller,
                externalDisplay: externalDisplay,
                showKeyboard: $showKeyboard,
                showAirPlayMenu: $showAirPlayMenu
            )
            TouchpadView(
                controller: controller,
                showKeyboard: $showKeyboard,
                useSystemKeyboard: $useSystemKeyboard
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var airPlayDialogMessage: String {
        switch externalDisplay.kind {
        case .dedicated:
            if externalDisplay.useExtendedLayout {
                return "扩展模式已启用：电视显示远程桌面，本机为触控板。"
            }
            return "第二屏已连接，正在把远程桌面输出到电视…"
        case .airplayPending:
            return """
            1. 保持本 App 在前台（不要切到桌面）
            2. 若电视仍在镜像手机桌面，请断开 AirPlay 后重新连接
            3. 连接成功后 App 会自动接管电视，显示远程桌面
            """
        case .mirrored:
            return "当前为镜像模式。点「切换为扩展模式」可让电视单独显示远程桌面。"
        case .none:
            return """
            1. 先进入远程会话并保持 App 在前台
            2. 控制中心 → 屏幕镜像 → 选择电视
            3. 返回 App，点「刷新检测」
            """
        }
    }

    @ViewBuilder
    private var airPlayDialogActions: some View {
        Button("启用扩展模式（电视显示桌面）") {
            externalDisplay.applyMode(.extended)
            externalDisplay.refreshConnection()
        }
        if externalDisplay.kind == .mirrored {
            Button("切换为扩展模式") {
                externalDisplay.applyMode(.extended)
                externalDisplay.refreshConnection()
            }
        }
        Button("刷新检测") {
            externalDisplay.refreshConnection()
        }
        if externalDisplay.kind != .none, externalDisplay.kind != .mirrored {
            Button("改用镜像（不推荐）") {
                externalDisplay.applyMode(.mirror)
            }
        }
        Button("取消", role: .cancel) {}
    }

    private var sessionSettingsSheet: some View {
        NavigationStack {
            Form {
                Section("色彩模式") {
                    Picker("模式", selection: Binding(
                        get: { controller.colorMode },
                        set: { controller.setColorMode($0, locked: controller.lockColorMode) }
                    )) {
                        ForEach(ColorMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("锁定", isOn: Binding(
                        get: { controller.lockColorMode },
                        set: { controller.setColorMode(controller.colorMode, locked: $0) }
                    ))
                }

                Section("分辨率") {
                    TextField("宽度", text: $resolutionWidth).keyboardType(.numberPad)
                    TextField("高度", text: $resolutionHeight).keyboardType(.numberPad)
                    Button("应用分辨率") {
                        guard let w = Int(resolutionWidth), let h = Int(resolutionHeight) else { return }
                        Task { await controller.changeResolution(width: w, height: h) }
                    }
                }

                Section("音频") {
                    Text("输出：\(controller.audioManager.routeDescription)")
                    Button("切换免提") {
                        try? controller.audioManager.setSpeakerOn(true)
                    }
                    Button("切换听筒") {
                        try? controller.audioManager.setSpeakerOn(false)
                    }
                }

                Section("第二屏（扩展模式）") {
                    if externalDisplay.isExternalConnected {
                        Text(externalDisplay.statusCaption)
                            .foregroundStyle(.secondary)
                        if externalDisplay.canUseExtendedMode {
                            Picker("模式", selection: Binding(
                                get: { externalDisplay.preferredMode },
                                set: { externalDisplay.applyMode($0) }
                            )) {
                                Text(ExternalDisplayMode.extended.displayName).tag(ExternalDisplayMode.extended)
                                Text(ExternalDisplayMode.mirror.displayName).tag(ExternalDisplayMode.mirror)
                            }
                        }
                        Button("刷新第二屏检测") {
                            externalDisplay.refreshConnection()
                        }
                    } else {
                        Text("未检测到电视。请先连接 AirPlay，并保持 App 在前台。")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("网络") {
                    Text("档位：\(controller.networkMonitor.tier.rawValue)")
                    Text("估算码率：\(controller.networkMonitor.estimatedKbps) kbps")
                }

                Section {
                    Text("通话期间请保持 App 在前台，锁屏可能导致麦克风中断。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("会话设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showSettings = false }
                }
            }
            .onAppear {
                resolutionWidth = String(host.effectiveWidth)
                resolutionHeight = String(host.effectiveHeight)
            }
        }
    }

    private func connect() async {
        do {
            let password = try store.password(for: host) ?? ""
            if password.isEmpty {
                controller.reportLocalError("未找到保存的密码，请编辑主机重新保存。")
                return
            }
            await controller.connect(to: host, password: password)
        } catch {
            controller.reportLocalError(error.localizedDescription)
        }
    }

    private func disconnectAndDismiss() async {
        await controller.disconnect()
        dismiss()
    }
}

import SwiftUI

/// 未就绪第二屏时的引导页（本 App 仅支持电视扩展模式）
struct SecondScreenGuideView: View {
    @ObservedObject var controller: RDPSessionController
    @ObservedObject var externalDisplay: ExternalDisplayManager
    var onRefresh: () -> Void
    var onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            guideHeader
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    statusCard
                    stepsCard
                    actionButtons
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    private var guideHeader: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)
            Text(controller.state.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            Spacer()
            Button("断开", role: .destructive, action: onDisconnect)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.95))
    }

    private var hero: some View {
        VStack(spacing: 14) {
            Image(systemName: heroIcon)
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Text(heroTitle)
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(heroSubtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("第二屏状态", systemImage: "airplayvideo")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text(externalDisplay.statusCaption)
                .font(.body)
                .foregroundStyle(.white.opacity(0.85))
            if externalDisplay.isExternalConnected {
                Text("远程连接已建立，电视就绪后将自动显示桌面。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("连接步骤")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.blue.opacity(0.55), in: Circle())
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                externalDisplay.applyMode(.extended)
                onRefresh()
            } label: {
                Label("启用扩展模式", systemImage: "rectangle.expand.vertical")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onRefresh) {
                Label("刷新检测", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(.bottom, 8)
    }

    private var connectionColor: Color {
        switch controller.state {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        default: return .red
        }
    }

    private var heroIcon: String {
        switch externalDisplay.kind {
        case .none: return "tv"
        case .airplayPending: return "airplayvideo"
        case .mirrored: return "rectangle.on.rectangle"
        case .dedicated: return "tv.fill"
        }
    }

    private var heroTitle: String {
        switch externalDisplay.kind {
        case .none:
            return "请先连接电视"
        case .airplayPending:
            return "正在接管电视"
        case .mirrored:
            return "请切换为扩展模式"
        case .dedicated:
            return isExternalReady ? "即将就绪" : "第二屏准备中"
        }
    }

    private var heroSubtitle: String {
        switch externalDisplay.kind {
        case .none:
            return "RDP AirPlay 仅支持电视扩展模式：电视显示远程桌面，手机作为触控板。"
        case .airplayPending:
            return "AirPlay 已连接。请保持 App 在前台，等待系统分配独立电视画面。"
        case .mirrored:
            return "当前为屏幕镜像，无法使用触控板模式。请断开重连并选择扩展显示。"
        case .dedicated:
            return isExternalReady
                ? "第二屏已连接，正在切换到触控板界面…"
                : "检测到第二屏，正在挂载远程桌面输出窗口…"
        }
    }

    private var isExternalReady: Bool {
        externalDisplay.isExternalWindowReady
    }

    private var steps: [String] {
        switch externalDisplay.kind {
        case .none:
            return [
                "保持本 App 在前台，进入远程会话。",
                "从控制中心打开「屏幕镜像 / AirPlay」，选择你的 Apple TV 或电视。",
                "返回 App，点「刷新检测」。成功后手机将变为触控板。",
            ]
        case .airplayPending:
            return [
                "不要切到桌面或其它 App，保持 RDP AirPlay 在前台。",
                "若电视仍在镜像 iPhone 桌面，请断开 AirPlay 后重新连接。",
                "点「刷新检测」或等待几秒，App 会自动接管电视。",
            ]
        case .mirrored:
            return [
                "断开当前 AirPlay 连接。",
                "重新连接电视，并保持 App 在前台。",
                "点「启用扩展模式」，让电视单独显示远程桌面。",
            ]
        case .dedicated:
            return [
                "第二屏已识别，远程桌面将输出到电视。",
                "若长时间无画面，点「刷新检测」。",
                "就绪后本页会自动切换为触控板界面。",
            ]
        }
    }
}

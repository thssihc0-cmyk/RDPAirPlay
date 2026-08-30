import SwiftUI

/// 会话内连接栏（对齐 Microsoft Remote Desktop 顶部控制条）
struct SessionConnectionBar: View {
    @ObservedObject var controller: RDPSessionController
    @ObservedObject var externalDisplay: ExternalDisplayManager
    @Binding var showKeyboard: Bool
    @Binding var showAirPlayMenu: Bool

    var body: some View {
        HStack(spacing: 10) {
            statusIndicator
            Text(controller.state.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.92))
            if externalDisplay.isExternalConnected {
                Text(externalDisplayBadge)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.35), in: Capsule())
                    .foregroundStyle(.white)
            }
            Spacer()
            connectionButton(
                icon: controller.mouseMode.iconName,
                active: controller.mouseMode == .mousePointer,
                label: controller.mouseMode.displayName
            ) {
                controller.mouseMode.toggle()
            }
            connectionButton(
                icon: showKeyboard ? "keyboard.fill" : "keyboard",
                active: showKeyboard,
                label: "键盘"
            ) {
                showKeyboard.toggle()
            }
            connectionButton(
                icon: "airplayvideo",
                active: externalDisplay.isExternalConnected,
                label: "AirPlay"
            ) {
                showAirPlayMenu = true
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.95))
    }

    private var externalDisplayBadge: String {
        switch externalDisplay.kind {
        case .dedicated:
            return externalDisplay.useExtendedLayout ? "电视扩展" : "第二屏"
        case .airplayPending:
            return "接管中"
        case .mirrored:
            return "镜像"
        case .none:
            return "AirPlay"
        }
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
    }

    private var statusColor: Color {
        switch controller.state {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        default: return .red
        }
    }

    private func connectionButton(
        icon: String,
        active: Bool,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? Color.green : Color.white.opacity(0.92))
            .frame(minWidth: 52)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Color.white.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

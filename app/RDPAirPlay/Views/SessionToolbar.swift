import SwiftUI

struct SessionToolbar: View {
    @ObservedObject var controller: RDPSessionController
    @ObservedObject var externalDisplay: ExternalDisplayManager
    @Binding var showKeyboard: Bool
    @Binding var showAirPlayMenu: Bool
    @Binding var showSettings: Bool
    @ObservedObject var orientationManager: SessionOrientationManager
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showKeyboard.toggle()
            } label: {
                Label("键盘", systemImage: showKeyboard ? "keyboard.fill" : "keyboard")
            }
            .foregroundStyle(showKeyboard ? Color.green : Color.white)

            Button {
                controller.mouseMode.toggle()
            } label: {
                Label(controller.mouseMode.displayName, systemImage: controller.mouseMode.iconName)
            }
            .foregroundStyle(controller.mouseMode == .mousePointer ? Color.green : Color.white)

            Button {
                showAirPlayMenu = true
            } label: {
                Label(airPlayLabel, systemImage: "airplayvideo")
            }
            .foregroundStyle(externalDisplay.isExternalConnected ? Color.green : Color.white)

            Button {
                orientationManager.cyclePreference()
            } label: {
                Label(
                    orientationManager.preference.toolbarLabel,
                    systemImage: orientationManager.preference.iconName
                )
            }

            Menu {
                ForEach(ColorMode.allCases) { mode in
                    Button(mode.displayName) {
                        controller.setColorMode(mode, locked: controller.lockColorMode)
                    }
                }
            } label: {
                Label(controller.colorMode.displayName, systemImage: "circle.lefthalf.filled")
            }

            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
            }

            Button(role: .destructive, action: onDisconnect) {
                Label("断开", systemImage: "phone.down.fill")
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.88))
    }

    private var airPlayLabel: String {
        switch externalDisplay.kind {
        case .dedicated:
            return externalDisplay.useExtendedLayout ? "扩展" : "第二屏"
        case .airplayPending:
            return "连接中"
        case .mirrored:
            return "镜像"
        case .none:
            return "AirPlay"
        }
    }
}

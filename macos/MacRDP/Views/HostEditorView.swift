import SwiftUI

struct HostEditorView: View {
    @State var host: HostProfile
    @Binding var password: String
    let onSave: (HostProfile, String) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("显示名", text: $host.displayName)
                TextField("主机 / IP", text: $host.hostname)
                TextField("端口", value: $host.port, format: .number)
                TextField("用户名", text: $host.username)
                SecureField("密码", text: $password)
                Picker("分辨率", selection: $host.resolution) {
                    ForEach(ResolutionPreset.presets) { preset in
                        Text(preset.name).tag(preset)
                    }
                }
                Picker("色彩模式", selection: $host.colorMode) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("锁定色彩模式（F-WN-07）", isOn: $host.lockColorMode)
                Toggle("远程音频下行", isOn: $host.enableSpeaker)
            }
            .padding()

            HStack {
                Button("取消", action: onCancel)
                Spacer()
                Button("保存") {
                    if host.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
                        host.displayName = host.hostname
                    }
                    onSave(host, password)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(host.hostname.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 420, height: 440)
    }
}

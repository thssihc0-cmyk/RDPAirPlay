import SwiftUI

struct HostDetailView: View {
    let host: HostProfile
    @Binding var password: String
    let bridgeSummary: String
    let onConnect: () async -> Void
    let onEdit: () -> Void

    @State private var connecting = false

    var body: some View {
        Form {
            Section("主机") {
                LabeledContent("显示名", value: host.title)
                LabeledContent("地址", value: "\(host.hostname):\(host.port)")
                LabeledContent("用户", value: host.username)
                LabeledContent("分辨率", value: "\(host.effectiveWidth)×\(host.effectiveHeight)")
                LabeledContent("色彩", value: "\(host.colorMode.displayName)\(host.lockColorMode ? "（锁定）" : "")")
            }
            Section("凭据（Keychain）") {
                SecureField("密码", text: $password)
                Text("密码仅写入 Keychain，不明文落盘。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("内核") {
                LabeledContent("桥接", value: bridgeSummary)
            }
            Section {
                HStack {
                    Button("编辑") { onEdit() }
                    Spacer()
                    Button {
                        connecting = true
                        Task {
                            await onConnect()
                            connecting = false
                        }
                    } label: {
                        if connecting {
                            ProgressView()
                        } else {
                            Text("连接")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(host.hostname.isEmpty || connecting)
                }
            }
        }
        .padding()
        .navigationTitle(host.title)
    }
}

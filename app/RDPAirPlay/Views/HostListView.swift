import SwiftUI

/// F-CONN-01: 主机列表
struct HostListView: View {
    @EnvironmentObject private var store: HostStore
    @EnvironmentObject private var externalDisplay: ExternalDisplayManager
    @State private var editingHost: HostProfile?
    @State private var isCreating = false
    @State private var connectingHost: HostProfile?

    var body: some View {
        NavigationStack {
            Group {
                if store.hosts.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("暂无主机")
                            .font(.title2.bold())
                        Text("添加 Windows 远程桌面主机后开始连接。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Button("添加主机") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                } else {
                    List {
                        ForEach(store.hosts) { host in
                            HostRow(host: host) {
                                connectingHost = host
                            }
                            .swipeActions {
                                Button("编辑") { editingHost = host }
                                Button("删除", role: .destructive) {
                                    store.delete(host)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("RDP AirPlay")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreating = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editingHost) { host in
                HostEditorView(host: host) { updated, password in
                    try store.upsert(updated, password: password)
                }
            }
            .sheet(isPresented: $isCreating) {
                HostEditorView(host: nil) { updated, password in
                    try store.upsert(updated, password: password)
                }
            }
            .fullScreenCover(item: $connectingHost) { host in
                SessionView(host: host)
                    .environmentObject(store)
                    .environmentObject(externalDisplay)
            }
        }
    }
}

private struct HostRow: View {
    let host: HostProfile
    let onConnect: () -> Void

    var body: some View {
        Button(action: onConnect) {
            HStack(spacing: 12) {
                Image(systemName: "pc")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text(host.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(host.hostname):\(host.port) · \(host.effectiveWidth)×\(host.effectiveHeight)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(host.colorMode.displayName) · \(host.enableMicrophone ? "麦克风开" : "麦克风关")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    HostListView()
        .environmentObject(HostStore())
        .environmentObject(ExternalDisplayManager())
}

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var hostStore: HostStore
    @StateObject private var session = RDPSessionController()
    @State private var selectedHostID: UUID?
    @State private var editingHost: HostProfile?
    @State private var showEditor = false
    @State private var passwordDraft = ""

    var body: some View {
        NavigationSplitView {
            hostList
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            if session.state == .connected || isActiveSession {
                SessionView(controller: session)
            } else if let host = selectedHost {
                HostDetailView(
                    host: host,
                    password: $passwordDraft,
                    bridgeSummary: session.bridgeSummary,
                    onConnect: { await connect(host) },
                    onEdit: {
                        editingHost = host
                        showEditor = true
                    }
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("macrdp").font(.largeTitle.bold())
                    Text("添加 Windows 主机后直连。首切片支持 Stub 画面与键鼠路径；FreeRDP 链接后走真实远程桌面。")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showEditor) {
            HostEditorView(
                host: editingHost ?? HostProfile(),
                password: $passwordDraft,
                onSave: { host, password in
                    try? hostStore.upsert(host, password: password.isEmpty ? nil : password)
                    selectedHostID = host.id
                    showEditor = false
                },
                onCancel: { showEditor = false }
            )
        }
        .onChange(of: selectedHostID) { newID in
            if let host = hostStore.hosts.first(where: { $0.id == newID }) {
                passwordDraft = hostStore.password(for: host) ?? ""
            }
        }
    }

    private var selectedHost: HostProfile? {
        hostStore.hosts.first { $0.id == selectedHostID }
    }

    private var isActiveSession: Bool {
        switch session.state {
        case .connecting, .reconnecting: return true
        default: return false
        }
    }

    private var hostList: some View {
        List(selection: $selectedHostID) {
            ForEach(hostStore.hosts) { host in
                VStack(alignment: .leading, spacing: 2) {
                    Text(host.title).font(.headline)
                    Text("\(host.hostname):\(host.port) · \(host.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(host.id)
                .contextMenu {
                    Button("编辑") {
                        editingHost = host
                        passwordDraft = hostStore.password(for: host) ?? ""
                        showEditor = true
                    }
                    Button("删除", role: .destructive) {
                        hostStore.delete(host)
                        if selectedHostID == host.id { selectedHostID = nil }
                    }
                }
            }
        }
        .navigationTitle("主机")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editingHost = HostProfile()
                    passwordDraft = ""
                    showEditor = true
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }
        }
    }

    private func connect(_ host: HostProfile) async {
        await session.connect(host: host, password: passwordDraft)
    }
}

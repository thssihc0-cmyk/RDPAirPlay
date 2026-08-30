import SwiftUI

/// F-CONN-01 / F-CONN-03: 新增与编辑主机
struct HostEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (HostProfile, String?) throws -> Void

    @State private var displayName: String
    @State private var hostname: String
    @State private var port: String
    @State private var username: String
    @State private var password: String
    @State private var useCustomResolution: Bool
    @State private var selectedPreset: ResolutionPreset
    @State private var customWidth: String
    @State private var customHeight: String
    @State private var colorMode: ColorMode
    @State private var lockColorMode: Bool
    @State private var enableSpeaker: Bool
    @State private var enableMicrophone: Bool
    @State private var errorMessage: String?

    private let hostID: UUID
    private let isEditing: Bool

    init(host: HostProfile?, onSave: @escaping (HostProfile, String?) throws -> Void) {
        self.onSave = onSave
        if let host {
            hostID = host.id
            isEditing = true
            _displayName = State(initialValue: host.displayName)
            _hostname = State(initialValue: host.hostname)
            _port = State(initialValue: String(host.port))
            _username = State(initialValue: host.username)
            _password = State(initialValue: "")
            _useCustomResolution = State(initialValue: host.customWidth != nil)
            _selectedPreset = State(initialValue: host.resolution)
            _customWidth = State(initialValue: String(host.customWidth ?? host.resolution.width))
            _customHeight = State(initialValue: String(host.customHeight ?? host.resolution.height))
            _colorMode = State(initialValue: host.colorMode)
            _lockColorMode = State(initialValue: host.lockColorMode)
            _enableSpeaker = State(initialValue: host.enableSpeaker)
            _enableMicrophone = State(initialValue: host.enableMicrophone)
        } else {
            hostID = UUID()
            isEditing = false
            _displayName = State(initialValue: "")
            _hostname = State(initialValue: "")
            _port = State(initialValue: "3389")
            _username = State(initialValue: HostProfile.defaultUsername)
            _password = State(initialValue: "")
            _useCustomResolution = State(initialValue: false)
            _selectedPreset = State(initialValue: .presets[0])
            _customWidth = State(initialValue: "1280")
            _customHeight = State(initialValue: "720")
            _colorMode = State(initialValue: .fullColor)
            _lockColorMode = State(initialValue: false)
            _enableSpeaker = State(initialValue: true)
            _enableMicrophone = State(initialValue: true)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("主机") {
                    TextField("显示名称", text: $displayName)
                    TextField("地址", text: $hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("端口", text: $port)
                        .keyboardType(.numberPad)
                    TextField("用户名", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("支持 DOMAIN\\用户名 或 .\\administrator（本地账户）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField(isEditing ? "密码（留空则不修改）" : "密码", text: $password)
                }

                Section("分辨率") {
                    Toggle("自定义分辨率", isOn: $useCustomResolution)
                    if useCustomResolution {
                        TextField("宽度", text: $customWidth).keyboardType(.numberPad)
                        TextField("高度", text: $customHeight).keyboardType(.numberPad)
                    } else {
                        Picker("预设", selection: $selectedPreset) {
                            ForEach(ResolutionPreset.presets) { preset in
                                Text("\(preset.label) (\(preset.width)×\(preset.height))").tag(preset)
                            }
                        }
                    }
                }

                Section("画质与音频") {
                    Picker("色彩模式", selection: $colorMode) {
                        ForEach(ColorMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("锁定色彩模式", isOn: $lockColorMode)
                    Toggle("扬声器（远程声音）", isOn: $enableSpeaker)
                    Toggle("麦克风（远程录音）", isOn: $enableMicrophone)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isEditing ? "编辑主机" : "添加主机")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard !displayName.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "请填写显示名称"
            return
        }
        guard !hostname.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "请填写主机地址"
            return
        }
        guard let portValue = Int(port), (1...65535).contains(portValue) else {
            errorMessage = "端口无效"
            return
        }
        guard !username.isEmpty else {
            errorMessage = "请填写用户名"
            return
        }
        if !isEditing && password.isEmpty {
            errorMessage = "请填写密码"
            return
        }

        var customW: Int?
        var customH: Int?
        if useCustomResolution {
            guard let w = Int(customWidth), let h = Int(customHeight),
                  ResolutionPreset.validate(width: w, height: h) else {
                errorMessage = "自定义分辨率无效"
                return
            }
            customW = w
            customH = h
        }

        let profile = HostProfile(
            id: hostID,
            displayName: displayName.trimmingCharacters(in: .whitespaces),
            hostname: hostname.trimmingCharacters(in: .whitespaces),
            port: portValue,
            username: username,
            resolution: selectedPreset,
            customWidth: customW,
            customHeight: customH,
            colorMode: colorMode,
            lockColorMode: lockColorMode,
            enableSpeaker: enableSpeaker,
            enableMicrophone: enableMicrophone
        )

        do {
            try onSave(profile, password.isEmpty ? nil : password)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

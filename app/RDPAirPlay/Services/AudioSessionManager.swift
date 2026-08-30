import AVFoundation

/// F-AUD-05 / F-AUD-06: 音频会话管理
@MainActor
final class AudioSessionManager: ObservableObject {
    @Published private(set) var isSpeakerEnabled = true
    @Published private(set) var isMicrophoneEnabled = false
    @Published private(set) var routeDescription = "默认"

    private let session = AVAudioSession.sharedInstance()

    /// 远程麦克风重定向前必须拿到系统授权，否则 FreeRDP audin-ios 无法打开 AudioQueue
    func requestMicrophoneAccessIfNeeded() async -> Bool {
        switch session.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                session.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }

    func configureForRemoteDesktop(speaker: Bool, microphone: Bool) throws {
        isSpeakerEnabled = speaker
        isMicrophoneEnabled = microphone

        var category: AVAudioSession.Category = .playback
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth]

        if speaker && microphone {
            category = .playAndRecord
            options = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .mixWithOthers]
        } else if microphone {
            category = .playAndRecord
            options = [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
        }

        try session.setCategory(category, mode: microphone ? .voiceChat : .default, options: options)
        try session.setActive(true, options: [])
        if microphone {
            try session.setPreferredInputNumberOfChannels(1)
        }
        updateRouteDescription()
    }

    func setSpeakerOn(_ enabled: Bool) throws {
        if enabled {
            try session.overrideOutputAudioPort(.speaker)
        } else {
            try session.overrideOutputAudioPort(.none)
        }
        isSpeakerEnabled = enabled
        updateRouteDescription()
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isMicrophoneEnabled = false
    }

    private func updateRouteDescription() {
        let outputs = session.currentRoute.outputs.map(\.portName).joined(separator: ", ")
        routeDescription = outputs.isEmpty ? "默认" : outputs
    }
}

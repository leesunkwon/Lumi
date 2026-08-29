//
//  AudioRoute.swift
//  MetaGemini
//

import AVFoundation
import Foundation

enum GlassesAudioRouteError: LocalizedError {
    case glassesMicrophoneUnavailable
    case glassesMicrophoneNotSelected

    var errorDescription: String? {
        switch self {
        case .glassesMicrophoneUnavailable:
            return "Ray-Ban Meta 마이크를 찾지 못했습니다. 안경이 iPhone Bluetooth에 연결되어 있는지 확인해주세요."
        case .glassesMicrophoneNotSelected:
            return "안경 마이크로 전환하지 못했습니다. 다른 Bluetooth 오디오 기기를 끄고 다시 시도해주세요."
        }
    }
}

@MainActor
enum GlassesAudioRoute {
    static func activate() async throws {
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP]
        )
        try audioSession.setActive(true)

        guard let glassesPort = audioSession.availableInputs?.first(where: isGlassesPort) else {
            throw GlassesAudioRouteError.glassesMicrophoneUnavailable
        }

        try audioSession.setPreferredInput(glassesPort)
        try await Task.sleep(for: .milliseconds(250))

        let selectedPort = audioSession.currentRoute.inputs.first
        guard selectedPort?.portType == .bluetoothHFP, selectedPort?.uid == glassesPort.uid else {
            throw GlassesAudioRouteError.glassesMicrophoneNotSelected
        }
    }

    private static func isGlassesPort(_ port: AVAudioSessionPortDescription) -> Bool {
        guard port.portType == .bluetoothHFP else { return false }

        let name = port.portName.lowercased()
        return name.contains("ray-ban") || name.contains("meta") || name.contains("oakley")
    }
}

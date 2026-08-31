//
//  AudioRoute.swift
//  MetaGemini
//

import AVFoundation
import Foundation

enum LumiAudioDestination: Equatable {
    case glasses(String)
    case bluetooth(String)
    case iPhone

    var displayName: String {
        switch self {
        case .glasses(let name), .bluetooth(let name):
            return name
        case .iPhone:
            return "iPhone"
        }
    }
}

@MainActor
enum LumiAudioRoute {
    static func activate() async throws -> LumiAudioDestination {
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try audioSession.setActive(true)

        if let glassesPort = audioSession.availableInputs?.first(where: isGlassesPort),
           await selectHandsFreeDevice(glassesPort, in: audioSession) {
            return .glasses(glassesPort.portName)
        }

        if let bluetoothPort = audioSession.availableInputs?.first(where: isBluetoothHandsFreePort),
           await selectHandsFreeDevice(bluetoothPort, in: audioSession) {
            return .bluetooth(bluetoothPort.portName)
        }

        // 통화용 Bluetooth 기기가 없으면 iOS가 iPhone의 내장 입·출력 경로를 선택하게 둡니다.
        try audioSession.setPreferredInput(nil)
        try await Task.sleep(for: .milliseconds(100))
        return currentDestination(in: audioSession)
    }

    private static func selectHandsFreeDevice(
        _ port: AVAudioSessionPortDescription,
        in audioSession: AVAudioSession
    ) async -> Bool {
        do {
            try audioSession.setPreferredInput(port)
            try await Task.sleep(for: .milliseconds(250))

            let currentInput = audioSession.currentRoute.inputs.first
            return currentInput?.portType == .bluetoothHFP
                && currentInput?.uid == port.uid
                && audioSession.currentRoute.outputs.contains(where: isBluetoothHandsFreePort)
        } catch {
            return false
        }
    }

    private static func currentDestination(in audioSession: AVAudioSession) -> LumiAudioDestination {
        if let glassesPort = audioSession.currentRoute.outputs.first(where: isGlassesPort) {
            return .glasses(glassesPort.portName)
        }

        if let bluetoothPort = audioSession.currentRoute.outputs.first(where: isBluetoothPort) {
            return .bluetooth(bluetoothPort.portName)
        }

        return .iPhone
    }

    private static func isGlassesPort(_ port: AVAudioSessionPortDescription) -> Bool {
        guard port.portType == .bluetoothHFP else { return false }

        let name = port.portName.lowercased()
        return name.contains("ray-ban") || name.contains("meta") || name.contains("oakley")
    }

    private static func isBluetoothPort(_ port: AVAudioSessionPortDescription) -> Bool {
        [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE].contains(port.portType)
    }

    private static func isBluetoothHandsFreePort(_ port: AVAudioSessionPortDescription) -> Bool {
        port.portType == .bluetoothHFP
    }
}

//
//  AudioRoute.swift
//  MetaGemini
//

import AVFoundation
import Foundation

struct LumiAudioDeviceStatus: Equatable {
    let microphone: String
    let speaker: String

    static let checking = LumiAudioDeviceStatus(
        microphone: "확인 중",
        speaker: "확인 중"
    )
}

@MainActor
enum LumiAudioRoute {
    static func activate() async throws -> LumiAudioDeviceStatus {
        let audioSession = AVAudioSession.sharedInstance()

        try audioSession.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .defaultToSpeaker]
        )
        try audioSession.setActive(true)

        if let glassesPort = audioSession.availableInputs?.first(where: isGlassesPort),
           await selectHandsFreeDevice(glassesPort, in: audioSession) {
            return currentDeviceStatus(in: audioSession)
        }

        if let bluetoothPort = audioSession.availableInputs?.first(where: isBluetoothHandsFreePort),
           await selectHandsFreeDevice(bluetoothPort, in: audioSession) {
            return currentDeviceStatus(in: audioSession)
        }

        // 통화용 Bluetooth 기기가 없으면 iOS가 iPhone의 내장 입·출력 경로를 선택하게 둡니다.
        try audioSession.setPreferredInput(nil)
        try await Task.sleep(for: .milliseconds(100))
        return currentDeviceStatus(in: audioSession)
    }

    static func currentDeviceStatus() -> LumiAudioDeviceStatus {
        currentDeviceStatus(in: AVAudioSession.sharedInstance())
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

    private static func currentDeviceStatus(in audioSession: AVAudioSession) -> LumiAudioDeviceStatus {
        let input = audioSession.currentRoute.inputs.first
        let output = audioSession.currentRoute.outputs.first
        return LumiAudioDeviceStatus(
            microphone: input.map { displayName(for: $0, role: .microphone) } ?? "사용 가능한 마이크 없음",
            speaker: output.map { displayName(for: $0, role: .speaker) } ?? "사용 가능한 스피커 없음"
        )
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

    private enum DeviceRole {
        case microphone
        case speaker
    }

    private static func displayName(
        for port: AVAudioSessionPortDescription,
        role: DeviceRole
    ) -> String {
        if isGlassesPort(port) {
            return "Ray-Ban Meta"
        }

        if isBluetoothPort(port) {
            return port.portName
        }

        switch (port.portType, role) {
        case (.builtInMic, .microphone):
            return "iPhone 내장 마이크"
        case (.builtInSpeaker, .speaker):
            return "iPhone 스피커"
        case (.builtInReceiver, .speaker):
            return "iPhone 수화부"
        default:
            return port.portName
        }
    }
}

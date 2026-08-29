//
//  VoiceRecorder.swift
//  MetaGemini
//

import AVFoundation
import Foundation

enum VoiceRecorderError: LocalizedError {
    case microphonePermissionDenied
    case noActiveRecording

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "음성 질문을 위해 마이크 접근을 허용해주세요."
        case .noActiveRecording:
            return "진행 중인 음성 질문이 없습니다."
        }
    }
}

@MainActor
final class VoiceRecorder {
    private var recorder: AVAudioRecorder?

    func start() async throws {
        guard await hasRecordPermission() else {
            throw VoiceRecorderError.microphonePermissionDenied
        }

        try await GlassesAudioRoute.activate()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lumi-question-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        recorder.record()
        self.recorder = recorder
    }

    func stop() throws -> URL {
        guard let recorder else {
            throw VoiceRecorderError.noActiveRecording
        }

        recorder.stop()
        self.recorder = nil
        return recorder.url
    }

    private func hasRecordPermission() async -> Bool {
        let audioApplication = AVAudioApplication.shared

        switch audioApplication.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }
}

@MainActor
final class SpeechOutput {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) async throws {
        try await GlassesAudioRoute.activate()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}

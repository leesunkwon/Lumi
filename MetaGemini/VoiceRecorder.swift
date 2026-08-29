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

    func prepareForRecording() async throws {
        guard await hasRecordPermission() else {
            throw VoiceRecorderError.microphonePermissionDenied
        }

        try await GlassesAudioRoute.activate()
    }

    func startPreparedRecording() throws {
        guard recorder == nil else { return }

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
    private var player: AVAudioPlayer?

    func speak(_ speech: SynthesizedSpeech) async throws {
        try await GlassesAudioRoute.activate()

        player?.stop()

        let audioData = try speech.playableAudioData()
        let player = try AVAudioPlayer(data: audioData)
        player.prepareToPlay()

        guard player.play() else {
            throw SpeechOutputError.playbackFailed
        }

        self.player = player

        do {
            while player.isPlaying {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            player.stop()
            throw error
        }

        if self.player === player {
            self.player = nil
        }
    }
}

private enum SpeechOutputError: LocalizedError {
    case unsupportedAudioFormat
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedAudioFormat:
            return "Gemini 음성 데이터 형식을 재생할 수 없습니다."
        case .playbackFailed:
            return "안경에서 Gemini 음성 답변을 재생하지 못했습니다."
        }
    }
}

private extension SynthesizedSpeech {
    func playableAudioData() throws -> Data {
        let normalizedMimeType = mimeType.lowercased()
        if audioData.hasWaveHeader {
            return audioData
        }

        let needsWaveContainer = normalizedMimeType.hasPrefix("audio/l16")
            || normalizedMimeType.contains("pcm")
            || normalizedMimeType.contains("wav")
        guard needsWaveContainer else { return audioData }

        guard let dataSize = UInt32(exactly: audioData.count),
              let channelCount = UInt16(exactly: channelCount),
              let sampleRate = UInt32(exactly: sampleRate)
        else {
            throw SpeechOutputError.unsupportedAudioFormat
        }

        let bitsPerSample: UInt16 = 16
        let bytesPerSample = UInt32(bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(channelCount) * bytesPerSample
        let blockAlign = channelCount * (bitsPerSample / 8)

        var waveData = Data()
        waveData.appendASCII("RIFF")
        waveData.appendLittleEndian(36 + dataSize)
        waveData.appendASCII("WAVE")
        waveData.appendASCII("fmt ")
        waveData.appendLittleEndian(UInt32(16))
        waveData.appendLittleEndian(UInt16(1))
        waveData.appendLittleEndian(channelCount)
        waveData.appendLittleEndian(sampleRate)
        waveData.appendLittleEndian(byteRate)
        waveData.appendLittleEndian(blockAlign)
        waveData.appendLittleEndian(bitsPerSample)
        waveData.appendASCII("data")
        waveData.appendLittleEndian(dataSize)
        waveData.append(audioData)
        return waveData
    }
}

private extension Data {
    var hasWaveHeader: Bool {
        count >= 12
            && prefix(4).elementsEqual("RIFF".utf8)
            && dropFirst(8).prefix(4).elementsEqual("WAVE".utf8)
    }

    mutating func appendASCII(_ value: String) {
        append(contentsOf: value.utf8)
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}

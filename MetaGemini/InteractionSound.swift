//
//  InteractionSound.swift
//  MetaGemini
//

import AVFoundation
import Foundation

enum LumiInteractionSound {
    case recordingStarted
    case questionSent
    case waitingPulse

    fileprivate var tones: [Tone] {
        switch self {
        case .recordingStarted:
            return [
                Tone(frequency: 523.25, start: 0, duration: 0.06, amplitude: 0.22),
                Tone(frequency: 783.99, start: 0.07, duration: 0.09, amplitude: 0.18)
            ]
        case .questionSent:
            return [
                Tone(frequency: 493.88, start: 0, duration: 0.06, amplitude: 0.18),
                Tone(frequency: 369.99, start: 0.07, duration: 0.10, amplitude: 0.16)
            ]
        case .waitingPulse:
            return [
                Tone(frequency: 659.25, start: 0, duration: 0.08, amplitude: 0.12),
                Tone(frequency: 783.99, start: 0.10, duration: 0.07, amplitude: 0.09)
            ]
        }
    }
}

@MainActor
final class InteractionSoundPlayer {
    private var player: AVAudioPlayer?

    func play(_ sound: LumiInteractionSound) {
        player?.stop()

        guard let player = try? AVAudioPlayer(data: WAVSoundData.make(tones: sound.tones)) else {
            return
        }

        player.volume = 0.34
        player.prepareToPlay()
        guard player.play() else { return }
        self.player = player
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

fileprivate struct Tone {
    let frequency: Double
    let start: Double
    let duration: Double
    let amplitude: Double
}

private enum WAVSoundData {
    private static let sampleRate = 24_000

    static func make(tones: [Tone]) -> Data {
        let duration = (tones.map { $0.start + $0.duration }.max() ?? 0) + 0.03
        let sampleCount = max(1, Int(duration * Double(sampleRate)))
        var pcm = Data(capacity: sampleCount * MemoryLayout<Int16>.size)

        for index in 0..<sampleCount {
            let time = Double(index) / Double(sampleRate)
            let sample = tones.reduce(0.0) { value, tone in
                value + sampleValue(at: time, tone: tone)
            }
            let normalized = min(max(sample, -1), 1)
            var integerSample = Int16((normalized * Double(Int16.max)).rounded()).littleEndian
            withUnsafeBytes(of: &integerSample) { pcm.append(contentsOf: $0) }
        }

        var wave = Data()
        appendASCII("RIFF", to: &wave)
        appendLittleEndian(UInt32(36 + pcm.count), to: &wave)
        appendASCII("WAVE", to: &wave)
        appendASCII("fmt ", to: &wave)
        appendLittleEndian(UInt32(16), to: &wave)
        appendLittleEndian(UInt16(1), to: &wave)
        appendLittleEndian(UInt16(1), to: &wave)
        appendLittleEndian(UInt32(sampleRate), to: &wave)
        appendLittleEndian(UInt32(sampleRate * MemoryLayout<Int16>.size), to: &wave)
        appendLittleEndian(UInt16(MemoryLayout<Int16>.size), to: &wave)
        appendLittleEndian(UInt16(16), to: &wave)
        appendASCII("data", to: &wave)
        appendLittleEndian(UInt32(pcm.count), to: &wave)
        wave.append(pcm)
        return wave
    }

    private static func sampleValue(at time: Double, tone: Tone) -> Double {
        let progress = (time - tone.start) / tone.duration
        guard (0...1).contains(progress) else { return 0 }

        let attack = min(progress / 0.12, 1)
        let release = min((1 - progress) / 0.35, 1)
        let envelope = min(attack, release)
        return sin(2 * .pi * tone.frequency * (time - tone.start)) * tone.amplitude * envelope
    }

    private static func appendASCII(_ value: String, to data: inout Data) {
        data.append(contentsOf: value.utf8)
    }

    private static func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            data.append(contentsOf: bytes)
        }
    }
}

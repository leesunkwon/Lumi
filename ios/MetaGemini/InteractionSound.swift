//
//  InteractionSound.swift
//  MetaGemini
//

import AVFoundation
import Foundation

enum LumiInteractionSound: Equatable {
    case recordingStarted
    case questionSent
    case waitingPulse

    fileprivate var resourceName: String {
        switch self {
        case .recordingStarted:
            return "microphone-open"
        case .questionSent:
            return "microphone-close"
        case .waitingPulse:
            return "answer-waiting"
        }
    }

    fileprivate var shouldLoop: Bool {
        self == .waitingPulse
    }

    var playbackDelay: Duration {
        switch self {
        case .recordingStarted:
            return .milliseconds(2_350)
        case .questionSent:
            return .milliseconds(1_100)
        case .waitingPulse:
            return .zero
        }
    }
}

@MainActor
final class InteractionSoundPlayer {
    private var player: AVAudioPlayer?
    private var activeSound: LumiInteractionSound?

    func play(_ sound: LumiInteractionSound) {
        if activeSound == sound, player?.isPlaying == true {
            return
        }

        player?.stop()
        guard let url = resourceURL(for: sound),
              let player = try? AVAudioPlayer(contentsOf: url)
        else {
            activeSound = nil
            return
        }

        player.volume = sound == .waitingPulse ? 0.24 : 0.38
        player.numberOfLoops = sound.shouldLoop ? -1 : 0
        player.prepareToPlay()
        guard player.play() else { return }

        self.player = player
        activeSound = sound
    }

    func stop() {
        player?.stop()
        player = nil
        activeSound = nil
    }

    private func resourceURL(for sound: LumiInteractionSound) -> URL? {
        Bundle.main.url(forResource: sound.resourceName, withExtension: "mp3")
            ?? Bundle.main.urls(forResourcesWithExtension: "mp3", subdirectory: nil)?
                .first(where: { $0.deletingPathExtension().lastPathComponent == sound.resourceName })
    }
}

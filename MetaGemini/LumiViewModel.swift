//
//  LumiViewModel.swift
//  MetaGemini
//

import Foundation
import MWDATCore
import Observation

@Observable
@MainActor
final class LumiViewModel {
    var isGlassesAvailable = false
    var isRegistering = false
    var isRecording = false
    var isStartingVoice = false
    var isProcessing = false
    var isCapturingScene = false
    var isSpeaking = false
    var lastTranscript: String?
    var lastAnswer: String?
    var memoSearchQuery = ""
    var memos: [VoiceMemo] = []
    var isShowingError = false
    var errorMessage = ""

    var glassesStatusDetail = "Meta AI에서 Lumi를 등록한 뒤 안경을 착용해주세요."

    var glassesStatusTitle: String {
        isGlassesAvailable ? "Ray-Ban Meta 연결됨" : "안경 연결 필요"
    }

    var connectionButtonTitle: String {
        isGlassesAvailable ? "연결됨" : "Meta AI에서 Lumi 연결"
    }

    var isBusy: Bool {
        isStartingVoice || isRecording || isProcessing || isCapturingScene || isSpeaking
    }

    var filteredMemos: [VoiceMemo] {
        let query = memoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return memos }

        return memos.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.body.localizedCaseInsensitiveContains(query)
        }
    }

    @ObservationIgnored private let wearables: WearablesInterface
    @ObservationIgnored private let voiceRecorder = VoiceRecorder()
    @ObservationIgnored private let speechOutput = SpeechOutput()
    @ObservationIgnored private let gemini = GeminiService()
    @ObservationIgnored private let glassesCamera: GlassesCamera
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?

    init(wearables: WearablesInterface, configurationError: String? = nil) {
        self.wearables = wearables
        self.glassesCamera = GlassesCamera(wearables: wearables)
        self.memos = Self.loadMemos()

        if let configurationError {
            self.errorMessage = "Meta 안경 SDK를 초기화하지 못했습니다: \(configurationError)"
            self.isShowingError = true
        }

        registrationTask = Task { [weak self] in
            guard let self else { return }
            for await state in wearables.registrationStateStream() {
                self.updateRegistrationState(state)
            }
        }

        devicesTask = Task { [weak self] in
            guard let self else { return }
            for await devices in wearables.devicesStream() {
                self.isGlassesAvailable = !devices.isEmpty
                if !devices.isEmpty {
                    self.isRegistering = false
                }
                self.glassesStatusDetail = devices.isEmpty
                    ? "안경을 착용하고 Bluetooth 연결을 확인해주세요."
                    : "음성 질문과 장면 보기를 사용할 수 있어요."
            }
        }
    }

    deinit {
        registrationTask?.cancel()
        devicesTask?.cancel()
    }

    func connectGlasses() {
        guard !isRegistering, !isGlassesAvailable else { return }
        isRegistering = true

        Task {
            do {
                try await wearables.startRegistration()
            } catch {
                isRegistering = false
                show(error)
            }
        }
    }

    func handleMetaCallback(_ url: URL) {
        Task {
            do {
                _ = try await wearables.handleUrl(url)
            } catch {
                isRegistering = false
                show(error)
            }
        }
    }

    func toggleVoiceQuestion() {
        if isRecording {
            finishVoiceQuestion()
        } else {
            startVoiceQuestion()
        }
    }

    func describeScene() {
        guard !isBusy, isGlassesAvailable else { return }
        isCapturingScene = true

        Task {
            do {
                let photoData = try await glassesCamera.capturePhoto()
                let result = try await gemini.describeScene(imageData: photoData)
                apply(result)
                let speech = try await gemini.synthesizeSpeech(result.answer)
                isCapturingScene = false
                try await playSpeech(speech)
            } catch {
                isCapturingScene = false
                isSpeaking = false
                show(error)
            }
        }
    }

    func saveLatestAnswerAsMemo() {
        guard let lastAnswer else { return }

        let body = lastTranscript.map { "질문: \($0)\n\n답변: \(lastAnswer)" } ?? lastAnswer
        saveMemo(VoiceMemo(title: "Lumi 답변", body: body))
    }

    func dismissError() {
        isShowingError = false
    }

    private func startVoiceQuestion() {
        guard !isBusy, isGlassesAvailable else { return }
        isStartingVoice = true

        Task {
            defer { isStartingVoice = false }
            do {
                try await voiceRecorder.start()
                isRecording = true
            } catch {
                show(error)
            }
        }
    }

    private func finishVoiceQuestion() {
        do {
            let audioURL = try voiceRecorder.stop()
            isRecording = false
            isProcessing = true

            Task {
                defer {
                    try? FileManager.default.removeItem(at: audioURL)
                }

                do {
                    let result = try await gemini.answerVoiceQuestion(audioURL: audioURL)
                    apply(result)
                    let speech = try await gemini.synthesizeSpeech(result.answer)
                    isProcessing = false
                    try await playSpeech(speech)
                } catch {
                    isProcessing = false
                    isSpeaking = false
                    show(error)
                }
            }
        } catch {
            isRecording = false
            show(error)
        }
    }

    private func playSpeech(_ speech: SynthesizedSpeech) async throws {
        isSpeaking = true
        defer { isSpeaking = false }
        try await speechOutput.speak(speech)
    }

    private func apply(_ result: AssistantResult) {
        lastTranscript = result.transcript
        lastAnswer = result.answer

        if let memo = result.memo {
            saveMemo(VoiceMemo(title: memo.title, body: memo.body))
        }
    }

    private func updateRegistrationState(_ state: RegistrationState) {
        switch state {
        case .registered:
            isRegistering = false
            glassesStatusDetail = "등록되었습니다. 안경을 착용해 연결을 시작하세요."
        case .registering:
            isRegistering = true
            glassesStatusDetail = "Meta AI에서 Lumi 연결을 승인하는 중입니다."
        case .available:
            isRegistering = false
            glassesStatusDetail = "Meta AI에서 Lumi를 등록해주세요."
        case .unavailable:
            isRegistering = false
            glassesStatusDetail = "Meta AI 앱과 안경 연결 상태를 확인해주세요."
        @unknown default:
            isRegistering = false
            glassesStatusDetail = "안경 상태를 확인하는 중입니다."
        }
    }

    private func saveMemo(_ memo: VoiceMemo) {
        memos.insert(memo, at: 0)
        guard let data = try? JSONEncoder().encode(memos) else { return }
        UserDefaults.standard.set(data, forKey: Self.memosKey)
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private static let memosKey = "lumi.voice-memos"

    private static func loadMemos() -> [VoiceMemo] {
        guard let data = UserDefaults.standard.data(forKey: memosKey),
              let memos = try? JSONDecoder().decode([VoiceMemo].self, from: data)
        else {
            return []
        }

        return memos.sorted { $0.createdAt > $1.createdAt }
    }
}

extension LumiViewModel {
    static var preview: LumiViewModel {
        LumiViewModel(wearables: Wearables.shared)
    }
}

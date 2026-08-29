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
    var conversations: [ConversationSession] = []
    var activeConversationID: UUID?
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

    var activeConversationMessages: [ConversationMessage] {
        conversation(for: activeConversationID)?.messages ?? []
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

        let storedConversations = Self.loadConversations()
        let initialConversation = ConversationSession()
        self.conversations = storedConversations.isEmpty ? [initialConversation] : storedConversations

        let storedActiveConversationID = UserDefaults.standard.string(forKey: Self.activeConversationKey)
            .flatMap(UUID.init(uuidString:))
        if let storedActiveConversationID,
           self.conversations.contains(where: { $0.id == storedActiveConversationID }) {
            self.activeConversationID = storedActiveConversationID
        } else {
            self.activeConversationID = self.conversations.first?.id
        }

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
        let conversationID = activeConversationID
        let conversationHistory = conversation(for: conversationID)?.messages ?? []

        Task {
            do {
                let photoData = try await glassesCamera.capturePhoto()
                let result = try await gemini.describeScene(
                    imageData: photoData,
                    conversationHistory: conversationHistory
                )
                apply(
                    result,
                    fallbackUserMessage: "지금 보는 장면을 설명해줘.",
                    conversationID: conversationID
                )
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

    @discardableResult
    func startNewConversation() -> UUID {
        let conversation = ConversationSession()
        conversations.insert(conversation, at: 0)
        activeConversationID = conversation.id
        lastTranscript = nil
        lastAnswer = nil
        saveConversations()
        return conversation.id
    }

    func selectConversation(_ id: UUID) {
        guard let conversation = conversation(for: id) else { return }
        activeConversationID = id
        lastTranscript = conversation.messages.last(where: { $0.role == .user })?.text
        lastAnswer = conversation.messages.last(where: { $0.role == .assistant })?.text
        saveConversations()
    }

    func conversation(for id: UUID?) -> ConversationSession? {
        guard let id else { return nil }
        return conversations.first { $0.id == id }
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
            let conversationID = activeConversationID
            let conversationHistory = conversation(for: conversationID)?.messages ?? []

            Task {
                defer {
                    try? FileManager.default.removeItem(at: audioURL)
                }

                do {
                    let result = try await gemini.answerVoiceQuestion(
                        audioURL: audioURL,
                        conversationHistory: conversationHistory
                    )
                    apply(
                        result,
                        fallbackUserMessage: "음성 질문",
                        conversationID: conversationID
                    )
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

    private func apply(
        _ result: AssistantResult,
        fallbackUserMessage: String,
        conversationID: UUID?
    ) {
        let transcript = result.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessage = (transcript?.isEmpty == false ? transcript : nil) ?? fallbackUserMessage
        appendConversationTurn(
            userMessage: userMessage,
            assistantMessage: result.answer,
            conversationID: conversationID
        )

        if activeConversationID == conversationID {
            lastTranscript = transcript
            lastAnswer = result.answer
        }

        if let memo = result.memo {
            saveMemo(VoiceMemo(title: memo.title, body: memo.body))
        }
    }

    private func appendConversationTurn(
        userMessage: String,
        assistantMessage: String,
        conversationID: UUID?
    ) {
        guard let conversationID,
              let index = conversations.firstIndex(where: { $0.id == conversationID })
        else {
            return
        }

        var conversation = conversations[index]
        conversation.messages.append(
            ConversationMessage(role: .user, text: userMessage)
        )
        conversation.messages.append(
            ConversationMessage(role: .assistant, text: assistantMessage)
        )
        conversation.updatedAt = .now

        if conversation.title == "새 대화" {
            conversation.title = conversationTitle(for: userMessage)
        }

        conversations[index] = conversation
        conversations.sort { $0.updatedAt > $1.updatedAt }
        saveConversations()
    }

    private func conversationTitle(for text: String) -> String {
        let normalizedText = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalizedText.isEmpty else { return "새 대화" }
        return String(normalizedText.prefix(28))
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
    private static let conversationsKey = "lumi.conversations"
    private static let activeConversationKey = "lumi.active-conversation-id"

    private static func loadMemos() -> [VoiceMemo] {
        guard let data = UserDefaults.standard.data(forKey: memosKey),
              let memos = try? JSONDecoder().decode([VoiceMemo].self, from: data)
        else {
            return []
        }

        return memos.sorted { $0.createdAt > $1.createdAt }
    }

    private func saveConversations() {
        guard let data = try? JSONEncoder().encode(conversations) else { return }
        UserDefaults.standard.set(data, forKey: Self.conversationsKey)
        UserDefaults.standard.set(activeConversationID?.uuidString, forKey: Self.activeConversationKey)
    }

    private static func loadConversations() -> [ConversationSession] {
        guard let data = UserDefaults.standard.data(forKey: conversationsKey),
              let conversations = try? JSONDecoder().decode([ConversationSession].self, from: data)
        else {
            return []
        }

        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }
}

extension LumiViewModel {
    static var preview: LumiViewModel {
        LumiViewModel(wearables: Wearables.shared)
    }
}

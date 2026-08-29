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
    @ObservationIgnored private let interactionSounds = InteractionSoundPlayer()
    @ObservationIgnored private let gemini = GeminiService()
    @ObservationIgnored private let glassesCamera: GlassesCamera
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?
    @ObservationIgnored private var waitingSoundTask: Task<Void, Never>?

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
        waitingSoundTask?.cancel()
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
        startWaitingSounds()
        let conversationID = activeConversationID
        let conversation = conversation(for: conversationID)
        let userMemories = memos

        Task {
            do {
                let photoData = try await glassesCamera.capturePhoto()
                let result = try await gemini.describeScene(
                    question: "지금 보는 장면을 설명해줘.",
                    imageData: photoData,
                    conversation: conversation,
                    userMemories: userMemories
                )
                try await deliver(
                    result,
                    fallbackUserMessage: "지금 보는 장면을 설명해줘.",
                    conversationID: conversationID
                )
            } catch {
                isCapturingScene = false
                isSpeaking = false
                stopWaitingSounds()
                show(error)
            }
        }
    }

    func saveLatestAnswerToUserMemory() {
        guard let lastAnswer else { return }

        let title = lastTranscript.map(conversationTitle(for:)) ?? "Lumi 답변"
        saveUserMemory(VoiceMemo(title: title, body: lastAnswer))
    }

    func deleteUserMemory(id: UUID) {
        guard memos.contains(where: { $0.id == id }) else { return }
        memos.removeAll { $0.id == id }
        saveUserMemories()
    }

    func deleteAllUserMemories() {
        guard !memos.isEmpty else { return }
        memos.removeAll()
        memoSearchQuery = ""
        UserDefaults.standard.removeObject(forKey: Self.memosKey)
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
                try await voiceRecorder.prepareForRecording()
                interactionSounds.play(.recordingStarted)
                try await Task.sleep(for: .milliseconds(180))
                try voiceRecorder.startPreparedRecording()
                isRecording = true
            } catch {
                interactionSounds.stop()
                show(error)
            }
        }
    }

    private func finishVoiceQuestion() {
        do {
            let audioURL = try voiceRecorder.stop()
            isRecording = false
            isProcessing = true
            interactionSounds.play(.questionSent)
            startWaitingSounds()
            let conversationID = activeConversationID
            let conversation = conversation(for: conversationID)
            let userMemories = memos

            Task {
                defer {
                    try? FileManager.default.removeItem(at: audioURL)
                }

                do {
                    let intentResult = try await gemini.answerVoiceQuestion(
                        audioURL: audioURL,
                        conversation: conversation,
                        userMemories: userMemories
                    )
                    try await handleVoiceIntent(
                        intentResult,
                        conversationID: conversationID,
                        conversation: conversation,
                        userMemories: userMemories
                    )
                } catch {
                    isProcessing = false
                    isCapturingScene = false
                    isSpeaking = false
                    stopWaitingSounds()
                    show(error)
                }
            }
        } catch {
            isRecording = false
            interactionSounds.stop()
            show(error)
        }
    }

    private func handleVoiceIntent(
        _ result: AssistantResult,
        conversationID: UUID?,
        conversation: ConversationSession?,
        userMemories: [VoiceMemo]
    ) async throws {
        let userQuestion = result.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackUserMessage = (userQuestion?.isEmpty == false ? userQuestion : nil) ?? "음성 질문"

        switch result.action {
        case .answer:
            try await deliver(
                result,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )

        case .currentTime:
            let localTimeResult = AssistantResult(
                transcript: result.transcript,
                answer: currentTimeAnswer(for: result.timeDetail),
                userMemory: result.userMemory,
                shouldSaveUserMemory: result.shouldSaveUserMemory,
                action: .answer,
                timeDetail: nil
            )
            try await deliver(
                localTimeResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )

        case .captureScene:
            isProcessing = false
            isCapturingScene = true

            let photoData = try await glassesCamera.capturePhoto()
            let visualResult = try await gemini.describeScene(
                question: fallbackUserMessage,
                imageData: photoData,
                conversation: conversation,
                userMemories: userMemories
            )
            try await deliver(
                visualResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )
        }
    }

    private func deliver(
        _ result: AssistantResult,
        fallbackUserMessage: String,
        conversationID: UUID?
    ) async throws {
        apply(
            result,
            fallbackUserMessage: fallbackUserMessage,
            conversationID: conversationID
        )
        let speech = try await gemini.synthesizeSpeech(result.answer)
        stopWaitingSounds()
        isProcessing = false
        isCapturingScene = false
        try await playSpeech(speech)
    }

    private func currentTimeAnswer(for detail: TimeDetail?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current

        switch detail {
        case .time:
            formatter.dateFormat = "a h시 mm분"
            return "지금은 \(formatter.string(from: .now))이에요."
        case .date:
            formatter.dateFormat = "M월 d일 EEEE"
            return "오늘은 \(formatter.string(from: .now))이에요."
        case .dateTime, .none:
            formatter.dateFormat = "M월 d일 EEEE a h시 mm분"
            return "지금은 \(formatter.string(from: .now))이에요."
        }
    }

    private func playSpeech(_ speech: SynthesizedSpeech) async throws {
        isSpeaking = true
        defer { isSpeaking = false }
        try await speechOutput.speak(speech)
    }

    private func startWaitingSounds() {
        waitingSoundTask?.cancel()

        waitingSoundTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(360))

                while !Task.isCancelled {
                    self?.interactionSounds.play(.waitingPulse)
                    try await Task.sleep(for: .milliseconds(1_450))
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private func stopWaitingSounds() {
        waitingSoundTask?.cancel()
        waitingSoundTask = nil
        interactionSounds.stop()
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

        if result.shouldSaveUserMemory,
           let userMemory = result.userMemory,
           hasExplicitUserMemorySaveRequest(in: userMessage) {
            saveUserMemory(VoiceMemo(title: userMemory.title, body: userMemory.body))
        }
    }

    private func hasExplicitUserMemorySaveRequest(in text: String) -> Bool {
        let compactText = String(
            text.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains)
        )

        let refersToContent = [
            "이거", "이것", "이걸", "이건", "이내용", "그거", "그것", "그걸", "그건", "그내용",
            "방금말한", "지금말한", "앞에서말한", "앞의내용"
        ].contains { compactText.contains($0) }
        let requestsRemembering = [
            "기억해", "기억해줘", "기억해둬", "기억해놓", "메모해", "메모리에저장", "메모리저장", "메모리에남겨"
        ].contains { compactText.contains($0) }
        let namesUserMemory = ["사용자메모리", "내메모리", "개인메모리"].contains {
            compactText.contains($0)
        }
        let asksToStore = ["저장", "기억", "남겨"].contains { compactText.contains($0) }

        return (refersToContent && requestsRemembering) || (namesUserMemory && asksToStore)
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

    private func saveUserMemory(_ userMemory: VoiceMemo) {
        memos.insert(userMemory, at: 0)
        saveUserMemories()
    }

    private func saveUserMemories() {
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

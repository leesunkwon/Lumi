//
//  LumiViewModel.swift
//  MetaGemini
//

import CoreLocation
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
    var selectedMemoryCategory: UserMemoryCategory?
    var selectedMemoryDateFilter: UserMemoryDateFilter = .all
    var selectedMemoryDate = Date.now
    var memos: [VoiceMemo] = []
    var schedules: [LumiSchedule] = []
    var timers: [LumiTimer] = []
    var pendingAction: PendingLumiAction?
    var isShowingError = false
    var errorMessage = ""
    var voiceAudioDestination = "안경 우선"

    var glassesStatusDetail = "Meta AI에서 Lumi를 등록한 뒤 안경을 착용해주세요."

    var glassesStatusTitle: String {
        isGlassesAvailable ? "Ray-Ban Meta 연결됨" : "안경 연결 필요"
    }

    var connectionButtonTitle: String {
        isGlassesAvailable ? "연결됨" : "Meta AI에서 Lumi 연결"
    }

    var isBusy: Bool {
        isStartingVoice || isRecording || isProcessing || isCapturingScene || isSpeaking || pendingAction != nil
    }

    var filteredMemos: [VoiceMemo] {
        let query = memoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let allMemoryRecords = memos + scheduleMemoryRecords
        let categoryMemos = selectedMemoryCategory.map { category in
            allMemoryRecords.filter { $0.category == category }
        } ?? allMemoryRecords
        let datedMemos = categoryMemos.filter { matchesSelectedMemoryDate($0) }
        let filteredMemos: [VoiceMemo]
        if query.isEmpty {
            filteredMemos = datedMemos
        } else {
            filteredMemos = datedMemos.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.body.localizedCaseInsensitiveContains(query)
            }
        }

        return filteredMemos.sorted {
            memoryTimelineDate(for: $0) > memoryTimelineDate(for: $1)
        }
    }

    var hasMemoryRecords: Bool {
        !memos.isEmpty || !schedules.isEmpty
    }

    var hasStandaloneUserMemories: Bool {
        !memos.isEmpty
    }

    var hasActiveMemoryDateFilter: Bool {
        selectedMemoryDateFilter != .all
    }

    var hasActiveMemoryFilters: Bool {
        !memoSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedMemoryCategory != nil
            || hasActiveMemoryDateFilter
    }

    var upcomingSchedules: [LumiSchedule] {
        schedules
            .filter(\.isUpcoming)
            .sorted { $0.scheduledAt < $1.scheduledAt }
    }

    var activeTimers: [LumiTimer] {
        timers
            .filter { $0.isActive() }
            .sorted { $0.endsAt < $1.endsAt }
    }

    var activeConversationMessages: [ConversationMessage] {
        conversation(for: activeConversationID)?.messages ?? []
    }

    @ObservationIgnored private let wearables: WearablesInterface
    @ObservationIgnored private let voiceRecorder = VoiceRecorder()
    @ObservationIgnored private let speechOutput = SpeechOutput()
    @ObservationIgnored private let interactionSounds = InteractionSoundPlayer()
    @ObservationIgnored private let gemini = GeminiService()
    @ObservationIgnored private let weather = WeatherService()
    @ObservationIgnored private let locationProvider = CurrentLocationProvider()
    @ObservationIgnored private let notificationScheduler = LumiNotificationScheduler()
    @ObservationIgnored private let glassesCamera: GlassesCamera
    @ObservationIgnored private var registrationTask: Task<Void, Never>?
    @ObservationIgnored private var devicesTask: Task<Void, Never>?
    @ObservationIgnored private var waitingSoundTask: Task<Void, Never>?
    @ObservationIgnored private var timerCleanupTask: Task<Void, Never>?

    init(wearables: WearablesInterface, configurationError: String? = nil) {
        self.wearables = wearables
        self.glassesCamera = GlassesCamera(wearables: wearables)
        let storedMemos = Self.loadMemos()
        self.memos = Self.migrateLegacyScheduleMemos(storedMemos)
        self.schedules = Self.loadSchedules()
        self.timers = Self.loadTimers()
        self.removeExpiredTimers()

        Task {
            for timer in self.activeTimers {
                await LumiTimerLiveActivityManager.startOrUpdate(for: timer)
            }
        }

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

        if self.memos != storedMemos {
            saveUserMemories()
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
                    ? "안경을 연결하면 카메라를 쓸 수 있어요. 음성 대화는 iPhone 또는 Bluetooth 기기로 계속할 수 있어요."
                    : "음성 질문과 장면 보기를 사용할 수 있어요."
            }
        }

        timerCleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                self?.removeExpiredTimers()
            }
        }
    }

    deinit {
        registrationTask?.cancel()
        devicesTask?.cancel()
        waitingSoundTask?.cancel()
        timerCleanupTask?.cancel()
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

    @discardableResult
    func submitTextQuestion(_ text: String) -> Bool {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isBusy else { return false }

        isProcessing = true
        interactionSounds.play(.questionSent)
        startWaitingSounds(after: LumiInteractionSound.questionSent.playbackDelay)

        let conversationID = activeConversationID
        let conversation = conversation(for: conversationID)
        let userMemories = memos
        let currentSchedules = upcomingSchedules

        Task {
            do {
                let intentResult = try await gemini.answerTextQuestion(
                    question,
                    conversation: conversation,
                    userMemories: userMemories,
                    schedules: currentSchedules
                )
                try await handleVoiceIntent(
                    intentResult,
                    conversationID: conversationID,
                    conversation: conversation,
                    userMemories: userMemories,
                    schedules: currentSchedules
                )
            } catch {
                isProcessing = false
                isCapturingScene = false
                isSpeaking = false
                stopWaitingSounds()
                show(error)
            }
        }

        return true
    }

    func describeScene() {
        analyzeScene(
            question: "지금 보는 장면을 설명해줘.",
            fallbackUserMessage: "지금 보는 장면을 설명해줘."
        )
    }

    func translateScene() {
        analyzeScene(
            question: """
            사진에서 읽을 수 있는 텍스트를 찾아 자연스러운 한국어로 번역해줘.
            메뉴나 문서라면 보이는 순서대로 핵심 내용을 빠뜨리지 않고 번역하고,
            번역할 텍스트가 없거나 읽기 어렵다면 그 사실만 짧게 알려줘.
            """,
            fallbackUserMessage: "사진 속 텍스트를 한국어로 번역해줘."
        )
    }

    func saveCurrentPlace() {
        guard !isBusy, isGlassesAvailable else { return }
        isProcessing = true
        startWaitingSounds()
        let conversationID = activeConversationID
        let conversation = conversation(for: conversationID)
        let userMemories = memos
        let currentSchedules = upcomingSchedules
        let request = AssistantResult(
            transcript: "지금 있는 장소를 사진과 위치로 저장해줘.",
            answer: "",
            userMemory: nil,
            shouldSaveUserMemory: false,
            action: .savePlace,
            timeDetail: nil,
            weatherDetail: nil
        )

        Task {
            do {
                try await handleVoiceIntent(
                    request,
                    conversationID: conversationID,
                    conversation: conversation,
                    userMemories: userMemories,
                    schedules: currentSchedules
                )
            } catch {
                isCapturingScene = false
                isProcessing = false
                isSpeaking = false
                stopWaitingSounds()
                show(error)
            }
        }
    }

    private func analyzeScene(question: String, fallbackUserMessage: String) {
        guard !isBusy, isGlassesAvailable else { return }
        isCapturingScene = true
        startWaitingSounds()
        let conversationID = activeConversationID
        let conversation = conversation(for: conversationID)
        let userMemories = memos
        let currentSchedules = upcomingSchedules

        Task {
            do {
                let photoData = try await glassesCamera.capturePhoto()
                let result = try await gemini.describeScene(
                    question: question,
                    imageData: photoData,
                    conversation: conversation,
                    userMemories: userMemories,
                    schedules: currentSchedules
                )
                try await deliver(
                    result,
                    fallbackUserMessage: fallbackUserMessage,
                    conversationID: conversationID,
                    scenePhotoData: photoData
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

    func addUserMemory(title: String, body: String, category: UserMemoryCategory) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard category != .schedule, !normalizedTitle.isEmpty, !normalizedBody.isEmpty else { return }

        saveUserMemory(
            VoiceMemo(
                title: normalizedTitle,
                body: normalizedBody,
                category: category
            )
        )
    }

    func updateUserMemory(
        id: UUID,
        title: String,
        body: String,
        category: UserMemoryCategory
    ) {
        guard let existingMemory = memos.first(where: { $0.id == id }) else { return }

        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard category != .schedule, !normalizedTitle.isEmpty, !normalizedBody.isEmpty else { return }

        memos.removeAll { $0.id == id }
        saveUserMemory(
            VoiceMemo(
                id: id,
                title: normalizedTitle,
                body: normalizedBody,
                category: category,
                photoFilename: existingMemory.photoFilename,
                location: existingMemory.location,
                createdAt: existingMemory.createdAt
            )
        )
    }

    func deleteUserMemory(id: UUID) {
        guard let memory = memos.first(where: { $0.id == id }) else { return }
        if let photoFilename = memory.photoFilename {
            UserMemoryPhotoStore.delete(filename: photoFilename)
        }
        memos.removeAll { $0.id == id }
        saveUserMemories()
    }

    func deleteAllUserMemories() {
        guard !memos.isEmpty else { return }
        memos.compactMap(\.photoFilename).forEach(UserMemoryPhotoStore.delete)
        memos.removeAll()
        memoSearchQuery = ""
        selectedMemoryCategory = nil
        selectedMemoryDateFilter = .all
        selectedMemoryDate = .now
        UserDefaults.standard.removeObject(forKey: Self.memosKey)
    }

    func addSchedule(title: String, scheduledAt: Date, note: String? = nil) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, scheduledAt > .now else { return }

        Task {
            _ = await registerSchedule(
                title: normalizedTitle,
                scheduledAt: scheduledAt,
                note: note
            )
        }
    }

    func updateSchedule(id: UUID, title: String, scheduledAt: Date, note: String? = nil) {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = schedules.firstIndex(where: { $0.id == id }),
              !normalizedTitle.isEmpty,
              scheduledAt > .now
        else {
            return
        }

        let existingSchedule = schedules[index]
        let updatedSchedule = LumiSchedule(
            id: existingSchedule.id,
            title: normalizedTitle,
            scheduledAt: scheduledAt,
            note: note,
            createdAt: existingSchedule.createdAt
        )
        schedules[index] = updatedSchedule
        schedules.sort { $0.scheduledAt < $1.scheduledAt }
        saveSchedules()
        notificationScheduler.cancel(identifier: existingSchedule.notificationIdentifier)

        Task {
            _ = await notificationScheduler.scheduleReminder(for: updatedSchedule)
        }
    }

    func deleteSchedule(id: UUID) {
        guard let schedule = schedules.first(where: { $0.id == id }) else { return }
        schedules.removeAll { $0.id == id }
        saveSchedules()
        notificationScheduler.cancel(identifier: schedule.notificationIdentifier)
    }

    func schedule(forMemoryID id: UUID) -> LumiSchedule? {
        schedules.first { $0.id == id }
    }

    func cancelTimer(id: UUID) {
        guard let timer = timers.first(where: { $0.id == id }) else { return }
        timers.removeAll { $0.id == id }
        saveTimers()
        notificationScheduler.cancel(identifier: timer.notificationIdentifier)
        Task {
            await LumiTimerLiveActivityManager.end(timerID: timer.id)
        }
    }

    func pauseTimer(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              !timers[index].isPaused
        else {
            return
        }

        let remainingSeconds = timers[index].remainingSeconds()
        guard remainingSeconds > 0 else {
            cancelTimer(id: id)
            return
        }

        timers[index].pausedAt = .now
        timers[index].pausedRemainingSeconds = remainingSeconds
        let timer = timers[index]
        saveTimers()
        notificationScheduler.cancel(identifier: timer.notificationIdentifier)

        Task {
            await LumiTimerLiveActivityManager.startOrUpdate(for: timer)
        }
    }

    func resumeTimer(id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }),
              let remainingSeconds = timers[index].pausedRemainingSeconds,
              remainingSeconds > 0
        else {
            return
        }

        timers[index].startedAt = .now
        timers[index].endsAt = .now.addingTimeInterval(TimeInterval(remainingSeconds))
        timers[index].pausedAt = nil
        timers[index].pausedRemainingSeconds = nil
        let timer = timers[index]
        saveTimers()

        Task {
            _ = await notificationScheduler.scheduleCompletion(for: timer)
            await LumiTimerLiveActivityManager.startOrUpdate(for: timer)
        }
    }

    func handleLumiURL(_ url: URL) -> Bool {
        guard url.scheme == "lumi", url.host == "timer",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let action = components.queryItems?.first(where: { $0.name == "action" })?.value,
              let timerIDString = components.queryItems?.first(where: { $0.name == "id" })?.value,
              let timerID = UUID(uuidString: timerIDString)
        else {
            return false
        }

        switch action {
        case "pause":
            pauseTimer(id: timerID)
        case "resume":
            resumeTimer(id: timerID)
        case "cancel":
            cancelTimer(id: timerID)
        case "open":
            break
        default:
            return false
        }

        return true
    }

    func confirmPendingAction() {
        guard let pendingAction else { return }
        self.pendingAction = nil
        isProcessing = true
        startWaitingSounds()

        Task {
            do {
                try await handleVoiceIntent(
                    pendingAction.result,
                    conversationID: pendingAction.conversationID,
                    conversation: pendingAction.conversation,
                    userMemories: pendingAction.userMemories,
                    schedules: pendingAction.schedules,
                    bypassingActionConfirmation: true
                )
            } catch {
                isProcessing = false
                isCapturingScene = false
                isSpeaking = false
                stopWaitingSounds()
                show(error)
            }
        }
    }

    func cancelPendingAction() {
        guard let pendingAction else { return }
        self.pendingAction = nil

        let cancelledResult = AssistantResult(
            transcript: pendingAction.result.transcript,
            answer: "알겠어요. \(pendingAction.kind.cancellationAnswer)",
            userMemory: nil,
            shouldSaveUserMemory: false,
            action: .answer,
            timeDetail: nil,
            weatherDetail: nil
        )

        isProcessing = true
        startWaitingSounds()
        Task {
            do {
                try await deliver(
                    cancelledResult,
                    fallbackUserMessage: pendingAction.fallbackUserMessage,
                    conversationID: pendingAction.conversationID
                )
            } catch {
                isProcessing = false
                isCapturingScene = false
                isSpeaking = false
                stopWaitingSounds()
                show(error)
            }
        }
    }

    func discardPendingAction() {
        pendingAction = nil
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

    func clearMemoryFilters() {
        memoSearchQuery = ""
        selectedMemoryCategory = nil
        selectedMemoryDateFilter = .all
        selectedMemoryDate = .now
    }

    private func startVoiceQuestion() {
        guard !isBusy else { return }
        isStartingVoice = true

        Task {
            defer { isStartingVoice = false }
            do {
                let destination = try await voiceRecorder.prepareForRecording()
                voiceAudioDestination = destination.displayName
                interactionSounds.play(.recordingStarted)
                try await Task.sleep(for: LumiInteractionSound.recordingStarted.playbackDelay)
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
            startWaitingSounds(after: LumiInteractionSound.questionSent.playbackDelay)
            let conversationID = activeConversationID
            let conversation = conversation(for: conversationID)
            let userMemories = memos
            let currentSchedules = upcomingSchedules

            Task {
                defer {
                    try? FileManager.default.removeItem(at: audioURL)
                }

                do {
                    let intentResult = try await gemini.answerVoiceQuestion(
                        audioURL: audioURL,
                        conversation: conversation,
                        userMemories: userMemories,
                        schedules: currentSchedules
                    )
                    try await handleVoiceIntent(
                        intentResult,
                        conversationID: conversationID,
                        conversation: conversation,
                        userMemories: userMemories,
                        schedules: currentSchedules
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
        userMemories: [VoiceMemo],
        schedules: [LumiSchedule],
        bypassingActionConfirmation: Bool = false
    ) async throws {
        let userQuestion = result.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackUserMessage = (userQuestion?.isEmpty == false ? userQuestion : nil) ?? "음성 질문"

        if !bypassingActionConfirmation,
           LumiPreferences.confirmsActionsBeforeExecution,
           let kind = actionConfirmationKind(for: result, userMessage: fallbackUserMessage) {
            pendingAction = PendingLumiAction(
                kind: kind,
                result: result,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID,
                conversation: conversation,
                userMemories: userMemories,
                schedules: schedules
            )
            isProcessing = false
            isCapturingScene = false
            stopWaitingSounds()
            return
        }

        switch result.action {
        case .answer:
            if shouldCaptureParkingMemory(for: result, userMessage: fallbackUserMessage) {
                let correctedResult = AssistantResult(
                    transcript: result.transcript,
                    answer: "",
                    userMemory: result.userMemory,
                    shouldSaveUserMemory: result.shouldSaveUserMemory,
                    action: .saveParking,
                    timeDetail: nil,
                    weatherDetail: nil
                )
                try await handleVoiceIntent(
                    correctedResult,
                    conversationID: conversationID,
                    conversation: conversation,
                    userMemories: userMemories,
                    schedules: schedules,
                    bypassingActionConfirmation: bypassingActionConfirmation
                )
            } else if let fallbackSchedule = relativeScheduleDraft(
                from: fallbackUserMessage,
                userMemory: result.userMemory
            ) {
                let correctedResult = AssistantResult(
                    transcript: result.transcript,
                    answer: "",
                    userMemory: result.userMemory,
                    shouldSaveUserMemory: result.shouldSaveUserMemory,
                    action: .createSchedule,
                    timeDetail: nil,
                    weatherDetail: nil,
                    scheduleDetail: fallbackSchedule
                )
                try await handleVoiceIntent(
                    correctedResult,
                    conversationID: conversationID,
                    conversation: conversation,
                    userMemories: userMemories,
                    schedules: schedules,
                    bypassingActionConfirmation: bypassingActionConfirmation
                )
            } else {
                try await deliver(
                    result,
                    fallbackUserMessage: fallbackUserMessage,
                    conversationID: conversationID
                )
            }

        case .currentTime:
            let localTimeResult = AssistantResult(
                transcript: result.transcript,
                answer: currentTimeAnswer(for: result.timeDetail),
                userMemory: result.userMemory,
                shouldSaveUserMemory: result.shouldSaveUserMemory,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
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
                userMemories: userMemories,
                schedules: schedules
            )
            try await deliver(
                visualResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID,
                scenePhotoData: photoData
            )

        case .weather:
            let answer = try await weather.weatherAnswer(
                for: result.weatherDetail ?? WeatherRequest()
            )
            let weatherResult = AssistantResult(
                transcript: result.transcript,
                answer: answer,
                userMemory: result.userMemory,
                shouldSaveUserMemory: result.shouldSaveUserMemory,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
            )
            try await deliver(
                weatherResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )

        case .savePlace:
            isProcessing = false
            isCapturingScene = true

            let photoData = try await glassesCamera.capturePhoto()
            let location = try await locationProvider.currentLocation()
            let memoryLocation = await userMemoryLocation(from: location)
            let placeResult = AssistantResult(
                transcript: result.transcript,
                answer: "이곳을 장소 메모리에 저장했어요.",
                userMemory: UserMemoryDraft(
                    title: "저장한 장소",
                    body: memoryLocation.displayName,
                    category: .place
                ),
                shouldSaveUserMemory: true,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
            )
            try await deliver(
                placeResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID,
                scenePhotoData: photoData,
                userMemoryPhotoData: photoData,
                userMemoryLocation: memoryLocation
            )

        case .saveParking:
            isProcessing = false
            isCapturingScene = true

            let photoData = try await glassesCamera.capturePhoto()
            let location = try await locationProvider.currentLocation()
            let memoryLocation = await userMemoryLocation(from: location)
            let parkingDraft = result.userMemory ?? UserMemoryDraft(
                title: "주차 위치",
                body: memoryLocation.displayName,
                category: .parking
            )
            let parkingResult = AssistantResult(
                transcript: result.transcript,
                answer: "주차 위치를 사진과 위치 정보로 저장했어요.",
                userMemory: UserMemoryDraft(
                    title: parkingDraft.title,
                    body: parkingDraft.body,
                    category: .parking
                ),
                shouldSaveUserMemory: true,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
            )
            try await deliver(
                parkingResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID,
                scenePhotoData: photoData,
                userMemoryPhotoData: photoData,
                userMemoryLocation: memoryLocation
            )

        case .updateUserMemory:
            guard let update = resolvedUserMemoryUpdate(result.userMemoryUpdate) else {
                let clarificationResult = AssistantResult(
                    transcript: result.transcript,
                    answer: "수정할 사용자 메모리를 정확히 찾지 못했어요. 메모 제목이나 내용을 조금 더 알려주세요.",
                    userMemory: nil,
                    shouldSaveUserMemory: false,
                    action: .answer,
                    timeDetail: nil,
                    weatherDetail: nil
                )
                try await deliver(
                    clarificationResult,
                    fallbackUserMessage: fallbackUserMessage,
                    conversationID: conversationID
                )
                return
            }

            updateUserMemory(
                id: update.existing.id,
                title: update.updated.title,
                body: update.updated.body,
                category: update.updated.category
            )
            let updateResult = AssistantResult(
                transcript: result.transcript,
                answer: "‘\(update.existing.title)’ 메모리를 수정했어요.",
                userMemory: nil,
                shouldSaveUserMemory: false,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
            )
            try await deliver(
                updateResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )

        case .deleteUserMemory:
            guard let memory = resolvedUserMemoryDeletion(result.userMemoryDeletion) else {
                let clarificationResult = AssistantResult(
                    transcript: result.transcript,
                    answer: "삭제할 사용자 메모리를 정확히 찾지 못했어요. 메모 제목이나 내용을 조금 더 알려주세요.",
                    userMemory: nil,
                    shouldSaveUserMemory: false,
                    action: .answer,
                    timeDetail: nil,
                    weatherDetail: nil
                )
                try await deliver(
                    clarificationResult,
                    fallbackUserMessage: fallbackUserMessage,
                    conversationID: conversationID
                )
                return
            }

            deleteUserMemory(id: memory.id)
            let deletionResult = AssistantResult(
                transcript: result.transcript,
                answer: "‘\(memory.title)’ 메모리를 삭제했어요.",
                userMemory: nil,
                shouldSaveUserMemory: false,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
            )
            try await deliver(
                deletionResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )

        case .createSchedule:
            guard let draft = result.scheduleDetail,
                  let scheduledAt = scheduleDate(from: draft),
                  scheduledAt > .now,
                  !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                let clarificationResult = AssistantResult(
                    transcript: result.transcript,
                    answer: "일정을 등록할 날짜와 시간을 다시 알려주세요.",
                    userMemory: nil,
                    shouldSaveUserMemory: false,
                    action: .answer,
                    timeDetail: nil,
                    weatherDetail: nil
                )
                try await deliver(
                    clarificationResult,
                    fallbackUserMessage: fallbackUserMessage,
                    conversationID: conversationID
                )
                return
            }

            let notificationScheduled = await registerSchedule(
                title: draft.title,
                scheduledAt: scheduledAt,
                note: draft.note
            )
            let notificationAnswer = notificationScheduled
                ? "알림도 설정했어요."
                : "일정은 등록했어요. 알림을 받으려면 iPhone 설정에서 Lumi 알림을 허용해 주세요."
            let scheduleResult = AssistantResult(
                transcript: result.transcript,
                answer: "\(scheduleDateDescription(scheduledAt))에 \(draft.title) 일정을 등록했고, \(notificationAnswer)",
                userMemory: nil,
                shouldSaveUserMemory: false,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
            )
            try await deliver(
                scheduleResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )

        case .startTimer:
            guard let draft = result.timerDetail,
                  (1...604_800).contains(draft.durationSeconds)
            else {
                let clarificationResult = AssistantResult(
                    transcript: result.transcript,
                    answer: "타이머 시간을 다시 알려주세요. 예를 들어 8분 타이머처럼 말해 주세요.",
                    userMemory: nil,
                    shouldSaveUserMemory: false,
                    action: .answer,
                    timeDetail: nil,
                    weatherDetail: nil
                )
                try await deliver(
                    clarificationResult,
                    fallbackUserMessage: fallbackUserMessage,
                    conversationID: conversationID
                )
                return
            }

            let notificationScheduled = await registerTimer(
                title: draft.title,
                durationSeconds: draft.durationSeconds
            )
            let notificationAnswer = notificationScheduled
                ? "끝나면 알려드릴게요."
                : "타이머는 시작했어요. 알림을 받으려면 iPhone 설정에서 Lumi 알림을 허용해 주세요."
            let timerResult = AssistantResult(
                transcript: result.transcript,
                answer: "\(timerDurationDescription(draft.durationSeconds)) \(draft.title) 타이머를 시작했어요. \(notificationAnswer)",
                userMemory: nil,
                shouldSaveUserMemory: false,
                action: .answer,
                timeDetail: nil,
                weatherDetail: nil
            )
            try await deliver(
                timerResult,
                fallbackUserMessage: fallbackUserMessage,
                conversationID: conversationID
            )
        }
    }

    private func deliver(
        _ result: AssistantResult,
        fallbackUserMessage: String,
        conversationID: UUID?,
        scenePhotoData: Data? = nil,
        userMemoryPhotoData: Data? = nil,
        userMemoryLocation: UserMemoryLocation? = nil
    ) async throws {
        apply(
            result,
            fallbackUserMessage: fallbackUserMessage,
            conversationID: conversationID,
            scenePhotoData: scenePhotoData,
            userMemoryPhotoData: userMemoryPhotoData,
            userMemoryLocation: userMemoryLocation
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

    private func registerSchedule(
        title: String,
        scheduledAt: Date,
        note: String?
    ) async -> Bool {
        let schedule = LumiSchedule(title: title, scheduledAt: scheduledAt, note: note)
        schedules.append(schedule)
        schedules.sort { $0.scheduledAt < $1.scheduledAt }
        saveSchedules()
        return await notificationScheduler.scheduleReminder(for: schedule)
    }

    private func registerTimer(title: String, durationSeconds: Int) async -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let timer = LumiTimer(
            title: normalizedTitle.isEmpty ? "타이머" : normalizedTitle,
            endsAt: .now.addingTimeInterval(TimeInterval(durationSeconds))
        )
        timers.append(timer)
        timers.sort { $0.endsAt < $1.endsAt }
        saveTimers()
        await LumiTimerLiveActivityManager.startOrUpdate(for: timer)
        return await notificationScheduler.scheduleCompletion(for: timer)
    }

    private func scheduleDate(from draft: ScheduleDraft) -> Date? {
        let formatters: [ISO8601DateFormatter] = [
            ISO8601DateFormatter(),
            {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                return formatter
            }()
        ]

        return formatters.compactMap { $0.date(from: draft.scheduledAt) }.first
    }

    private func relativeScheduleDraft(
        from text: String,
        userMemory: UserMemoryDraft?
    ) -> ScheduleDraft? {
        let normalizedText = text.lowercased()
        let hasScheduleSubject = ["회의", "약속", "예약", "일정", "마감", "리마인더"].contains {
            normalizedText.contains($0)
        }
        let hasSaveRequest = ["등록", "추가", "기억", "메모", "기록", "저장", "알려줘"].contains {
            normalizedText.contains($0)
        }

        guard hasScheduleSubject,
              hasSaveRequest || userMemory?.category == .schedule,
              let duration = relativeDuration(in: text),
              (1...604_800).contains(duration)
        else {
            return nil
        }

        let fallbackTitle = relativeScheduleTitle(in: text)
        let title = userMemory?.category == .schedule
            ? userMemory?.title.trimmingCharacters(in: .whitespacesAndNewlines)
            : fallbackTitle
        let resolvedTitle = (title?.isEmpty == false ? title : nil) ?? "일정"
        let scheduledAt = Date.now.addingTimeInterval(TimeInterval(duration))
        let formatter = ISO8601DateFormatter()

        return ScheduleDraft(
            title: resolvedTitle,
            scheduledAt: formatter.string(from: scheduledAt),
            note: userMemory?.category == .schedule ? userMemory?.body : nil
        )
    }

    private func relativeDuration(in text: String) -> Int? {
        let pattern = #"(\d+)\s*(초|분|시간|일)\s*(뒤|후)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Int(text[valueRange])
        else {
            return nil
        }

        switch text[unitRange] {
        case "초": return value
        case "분": return value * 60
        case "시간": return value * 3_600
        case "일": return value * 86_400
        default: return nil
        }
    }

    private func relativeScheduleTitle(in text: String) -> String {
        let removablePhrases = [
            "등록해줘", "추가해줘", "기억해줘", "메모해줘", "기록해줘", "저장해줘", "알려줘",
            "일정을", "일정", "리마인더를", "리마인더"
        ]
        var title = text

        if let expression = try? NSRegularExpression(pattern: #"\d+\s*(초|분|시간|일)\s*(뒤|후)(에)?"#) {
            title = expression.stringByReplacingMatches(
                in: title,
                range: NSRange(title.startIndex..., in: title),
                withTemplate: ""
            )
        }

        for phrase in removablePhrases {
            title = title.replacingOccurrences(of: phrase, with: "")
        }

        let cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,!?"))

        return cleaned.isEmpty ? "일정" : cleaned
    }

    private func scheduleDateDescription(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "M월 d일 EEEE a h시 mm분"
        return formatter.string(from: date)
    }

    private func timerDurationDescription(_ durationSeconds: Int) -> String {
        let hours = durationSeconds / 3_600
        let minutes = (durationSeconds % 3_600) / 60
        let seconds = durationSeconds % 60

        if hours > 0, minutes > 0 { return "\(hours)시간 \(minutes)분" }
        if hours > 0 { return "\(hours)시간" }
        if minutes > 0, seconds > 0 { return "\(minutes)분 \(seconds)초" }
        if minutes > 0 { return "\(minutes)분" }
        return "\(seconds)초"
    }

    private func playSpeech(_ speech: SynthesizedSpeech) async throws {
        isSpeaking = true
        defer { isSpeaking = false }
        try await speechOutput.speak(speech)
    }

    private func startWaitingSounds(after delay: Duration = .milliseconds(360)) {
        waitingSoundTask?.cancel()

        waitingSoundTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.interactionSounds.play(.waitingPulse)
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
        conversationID: UUID?,
        scenePhotoData: Data? = nil,
        userMemoryPhotoData: Data? = nil,
        userMemoryLocation: UserMemoryLocation? = nil
    ) {
        let transcript = result.transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userMessage = (transcript?.isEmpty == false ? transcript : nil) ?? fallbackUserMessage
        let photoFilename = scenePhotoData.flatMap { try? ConversationPhotoStore.save($0) }
        appendConversationTurn(
            userMessage: userMessage,
            assistantMessage: result.answer,
            conversationID: conversationID,
            photoFilename: photoFilename
        )

        if activeConversationID == conversationID {
            lastTranscript = transcript
            lastAnswer = result.answer
        }

        let hasExplicitMemoryRequest = hasExplicitUserMemorySaveRequest(in: userMessage)
        if let userMemory = result.userMemory,
           userMemory.category != .schedule,
           hasExplicitMemoryRequest {
            let userMemoryPhotoFilename = userMemoryPhotoData.flatMap { try? UserMemoryPhotoStore.save($0) }
            saveUserMemory(
                VoiceMemo(
                    title: userMemory.title,
                    body: userMemory.body,
                    category: userMemory.category,
                    photoFilename: userMemoryPhotoFilename,
                    location: userMemoryLocation
                )
            )
        }
    }

    private func userMemoryLocation(from location: CLLocation) async -> UserMemoryLocation {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        let place = placemarks?.first
        let address = [
            place?.administrativeArea,
            place?.locality,
            place?.subLocality,
            place?.thoroughfare
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .reduce(into: [String]()) { values, value in
            if values.last != value {
                values.append(value)
            }
        }
        .joined(separator: " ")

        return UserMemoryLocation(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            address: address.isEmpty ? nil : address
        )
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
            "기억해", "기억해줘", "기억해둬", "기억해놓", "메모해", "기록해", "기록해줘", "기록해둬",
            "메모리에저장", "메모리저장", "메모리에남겨"
        ].contains { compactText.contains($0) }
        let directRememberRequest = [
            "기억해줘", "기억해둬", "기억해놓", "메모해줘", "메모해둬", "기록해줘", "기록해둬",
            "저장해줘", "메모리에저장", "메모리저장", "메모리에남겨"
        ].contains { compactText.contains($0) }
        let namesUserMemory = ["사용자메모리", "내메모리", "개인메모리"].contains {
            compactText.contains($0)
        }
        let namesCategorizedMemory = [
            "주차", "주차위치", "할일", "해야할일", "일정", "약속", "마감"
        ].contains { compactText.contains($0) }
        let asksToStore = ["저장", "기억", "메모", "기록", "남겨"].contains { compactText.contains($0) }

        return directRememberRequest
            || (refersToContent && requestsRemembering)
            || (namesUserMemory && asksToStore)
            || (namesCategorizedMemory && directRememberRequest)
    }

    private func shouldCaptureParkingMemory(
        for result: AssistantResult,
        userMessage: String
    ) -> Bool {
        result.shouldSaveUserMemory
            && result.userMemory?.category == .parking
            && hasExplicitUserMemorySaveRequest(in: userMessage)
    }

    private func resolvedUserMemoryUpdate(
        _ draft: UserMemoryUpdateDraft?
    ) -> (existing: VoiceMemo, updated: UserMemoryDraft)? {
        guard let draft,
              let existing = memos.first(where: { $0.id == draft.memoryID })
        else {
            return nil
        }

        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard draft.category != .schedule, !title.isEmpty, !body.isEmpty else {
            return nil
        }

        return (
            existing,
            UserMemoryDraft(title: title, body: body, category: draft.category)
        )
    }

    private func resolvedUserMemoryDeletion(
        _ draft: UserMemoryDeleteDraft?
    ) -> VoiceMemo? {
        guard let draft else { return nil }
        return memos.first { $0.id == draft.memoryID }
    }

    private func actionConfirmationKind(
        for result: AssistantResult,
        userMessage: String
    ) -> LumiActionConfirmationKind? {
        switch result.action {
        case .savePlace:
            return .place
        case .saveParking:
            return .parking
        case .updateUserMemory:
            guard let update = resolvedUserMemoryUpdate(result.userMemoryUpdate) else {
                return nil
            }
            return .updateUserMemory(existing: update.existing, updated: update.updated)
        case .deleteUserMemory:
            guard let memory = resolvedUserMemoryDeletion(result.userMemoryDeletion) else {
                return nil
            }
            return .deleteUserMemory(memory)
        case .createSchedule:
            guard let draft = result.scheduleDetail,
                  let scheduledAt = scheduleDate(from: draft),
                  scheduledAt > .now,
                  !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }
            return .schedule(draft, scheduledAt)
        case .startTimer:
            guard let draft = result.timerDetail,
                  (1...604_800).contains(draft.durationSeconds)
            else {
                return nil
            }
            return .timer(draft)
        case .answer:
            if shouldCaptureParkingMemory(for: result, userMessage: userMessage) {
                return .parking
            }
            if let draft = relativeScheduleDraft(from: userMessage, userMemory: result.userMemory),
               let scheduledAt = scheduleDate(from: draft) {
                return .schedule(draft, scheduledAt)
            }
            guard result.shouldSaveUserMemory,
                  let memory = result.userMemory,
                  memory.category != .schedule,
                  hasExplicitUserMemorySaveRequest(in: userMessage)
            else {
                return nil
            }
            return .userMemory(memory)
        case .captureScene, .currentTime, .weather:
            return nil
        }
    }

    private func appendConversationTurn(
        userMessage: String,
        assistantMessage: String,
        conversationID: UUID?,
        photoFilename: String?
    ) {
        guard let conversationID,
              let index = conversations.firstIndex(where: { $0.id == conversationID })
        else {
            return
        }

        var conversation = conversations[index]
        conversation.messages.append(
            ConversationMessage(
                role: .user,
                text: userMessage,
                photoFilename: photoFilename
            )
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
        memos.removeAll { $0.id == userMemory.id }
        if userMemory.category == .parking {
            memos
                .filter { $0.category == .parking }
                .compactMap(\.photoFilename)
                .forEach(UserMemoryPhotoStore.delete)
            memos.removeAll { $0.category == .parking }
        }
        memos.append(userMemory)
        memos.sort { $0.createdAt > $1.createdAt }
        saveUserMemories()
    }

    private func matchesSelectedMemoryDate(_ memory: VoiceMemo) -> Bool {
        let calendar = Calendar.current
        let referenceDate = memoryTimelineDate(for: memory)

        switch selectedMemoryDateFilter {
        case .all:
            return true
        case .today:
            return calendar.isDateInToday(referenceDate)
        case .yesterday:
            return calendar.isDateInYesterday(referenceDate)
        case .thisWeek:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return false }
            return week.contains(referenceDate)
        case .custom:
            return calendar.isDate(referenceDate, inSameDayAs: selectedMemoryDate)
        }
    }

    private var scheduleMemoryRecords: [VoiceMemo] {
        schedules.map { schedule in
            VoiceMemo(
                id: schedule.id,
                title: schedule.title,
                body: schedule.note ?? "",
                category: .schedule,
                createdAt: schedule.createdAt
            )
        }
    }

    private func memoryTimelineDate(for memory: VoiceMemo) -> Date {
        schedule(forMemoryID: memory.id)?.scheduledAt ?? memory.createdAt
    }

    private func saveUserMemories() {
        guard let data = try? JSONEncoder().encode(memos) else { return }
        UserDefaults.standard.set(data, forKey: Self.memosKey)
    }

    private static func migrateLegacyScheduleMemos(_ memos: [VoiceMemo]) -> [VoiceMemo] {
        memos.map { memory in
            guard memory.category == .schedule else { return memory }

            return VoiceMemo(
                id: memory.id,
                title: memory.title,
                body: memory.body,
                category: .general,
                photoFilename: memory.photoFilename,
                location: memory.location,
                createdAt: memory.createdAt
            )
        }
    }

    private func removeExpiredTimers(referenceDate: Date = .now) {
        let active = timers.filter { $0.isActive(at: referenceDate) }
        guard active.count != timers.count else { return }
        let expiredTimerIDs = Set(timers.map(\.id)).subtracting(Set(active.map(\.id)))
        timers = active
        saveTimers()

        Task {
            for timerID in expiredTimerIDs {
                await LumiTimerLiveActivityManager.end(timerID: timerID)
            }
        }
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        isShowingError = true
    }

    private static let memosKey = "lumi.voice-memos"
    private static let schedulesKey = "lumi.schedules"
    private static let timersKey = "lumi.timers"
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

    private func saveSchedules() {
        guard let data = try? JSONEncoder().encode(schedules) else { return }
        UserDefaults.standard.set(data, forKey: Self.schedulesKey)
    }

    private static func loadSchedules() -> [LumiSchedule] {
        guard let data = UserDefaults.standard.data(forKey: schedulesKey),
              let schedules = try? JSONDecoder().decode([LumiSchedule].self, from: data)
        else {
            return []
        }

        return schedules.sorted { $0.scheduledAt < $1.scheduledAt }
    }

    private func saveTimers() {
        guard let data = try? JSONEncoder().encode(timers) else { return }
        UserDefaults.standard.set(data, forKey: Self.timersKey)
    }

    private static func loadTimers() -> [LumiTimer] {
        guard let data = UserDefaults.standard.data(forKey: timersKey),
              let timers = try? JSONDecoder().decode([LumiTimer].self, from: data)
        else {
            return []
        }

        return timers.sorted { $0.endsAt < $1.endsAt }
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

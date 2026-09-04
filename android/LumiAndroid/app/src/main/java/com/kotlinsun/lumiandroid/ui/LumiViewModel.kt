package com.kotlinsun.lumiandroid.ui

import android.app.Application
import android.app.AlarmManager
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.kotlinsun.lumiandroid.data.ConversationEntity
import com.kotlinsun.lumiandroid.data.ConversationWithMessages
import com.kotlinsun.lumiandroid.data.LumiDatabase
import com.kotlinsun.lumiandroid.data.LumiPreferences
import com.kotlinsun.lumiandroid.data.LumiRepository
import com.kotlinsun.lumiandroid.data.MemoryCategory
import com.kotlinsun.lumiandroid.data.MemoryEntity
import com.kotlinsun.lumiandroid.data.MessageRole
import com.kotlinsun.lumiandroid.data.PhotoStore
import com.kotlinsun.lumiandroid.data.PreferencesStore
import com.kotlinsun.lumiandroid.data.ResponseTone
import com.kotlinsun.lumiandroid.data.ScheduleEntity
import com.kotlinsun.lumiandroid.data.TimerEntity
import com.kotlinsun.lumiandroid.service.AssistantAction
import com.kotlinsun.lumiandroid.service.AssistantResult
import com.kotlinsun.lumiandroid.service.GeminiService
import com.kotlinsun.lumiandroid.service.GlassesController
import com.kotlinsun.lumiandroid.service.LocationService
import com.kotlinsun.lumiandroid.service.LumiNotifications
import com.kotlinsun.lumiandroid.service.SpeechPlayer
import com.kotlinsun.lumiandroid.service.VoiceRecorder
import com.kotlinsun.lumiandroid.service.WeatherService
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import org.json.JSONArray

enum class AssistantStatus(val label: String) {
    IDLE("준비됨"),
    RECORDING("듣는 중"),
    THINKING("생각하는 중"),
    CAPTURING("안경으로 보는 중"),
    SPEAKING("답변 재생 중"),
}

enum class SceneMode { DESCRIBE, TRANSLATE, SAVE_PLACE, SAVE_PARKING }

data class LumiUiState(
    val conversations: List<ConversationWithMessages> = emptyList(),
    val memories: List<MemoryEntity> = emptyList(),
    val schedules: List<ScheduleEntity> = emptyList(),
    val timers: List<TimerEntity> = emptyList(),
    val preferences: LumiPreferences = LumiPreferences(),
    val selectedConversationId: String? = null,
    val status: AssistantStatus = AssistantStatus.IDLE,
    val lastAnswer: String? = null,
    val error: String? = null,
    val pendingAction: AssistantResult? = null,
    val pendingSceneMode: SceneMode? = null,
) {
    val activeConversation: ConversationWithMessages?
        get() = conversations.firstOrNull { it.conversation.id == selectedConversationId } ?: conversations.firstOrNull()
    val upcomingSchedules: List<ScheduleEntity>
        get() = schedules.filter { it.scheduledAt > System.currentTimeMillis() }
    val activeTimers: List<TimerEntity>
        get() = timers.filter { it.remainingSeconds() > 0 || it.isPaused }
}

class LumiViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = LumiRepository(LumiDatabase.create(application))
    private val preferencesStore = PreferencesStore(application)
    private val photoStore = PhotoStore(application)
    private val gemini = GeminiService()
    private val weather = WeatherService()
    private val location = LocationService(application)
    private val recorder = VoiceRecorder(application)
    private val speechPlayer = SpeechPlayer(application)
    val glasses = GlassesController()

    private val _state = MutableStateFlow(LumiUiState())
    val state: StateFlow<LumiUiState> = _state.asStateFlow()

    init {
        viewModelScope.launch { repository.conversations.collectLatest { update { copy(conversations = it, selectedConversationId = selectedConversationId ?: it.firstOrNull()?.conversation?.id) } } }
        viewModelScope.launch { repository.memories.collectLatest { update { copy(memories = it) } } }
        viewModelScope.launch { repository.schedules.collectLatest { update { copy(schedules = it) } } }
        viewModelScope.launch { repository.timers.collectLatest { update { copy(timers = it.filter { timer -> timer.remainingSeconds() > 0 || timer.isPaused }) } } }
        viewModelScope.launch { preferencesStore.preferences.collectLatest { update { copy(preferences = it) } } }
    }

    fun selectConversation(id: String) = update { copy(selectedConversationId = id) }

    fun newConversation() {
        viewModelScope.launch {
            val conversation = repository.newConversation()
            update { copy(selectedConversationId = conversation.id) }
        }
    }

    fun dismissError() = update { copy(error = null) }
    fun clearPendingAction() = update { copy(pendingAction = null) }
    fun reportError(error: Throwable) = showError(error)

    fun updatePreferences(transform: (LumiPreferences) -> LumiPreferences) {
        viewModelScope.launch { preferencesStore.update(transform) }
    }

    fun submitText(text: String) {
        val prompt = text.trim()
        if (prompt.isBlank()) return
        viewModelScope.launch { ask(prompt) }
    }

    fun startRecording() {
        speechPlayer.stop()
        runCatching { recorder.start() }
            .onSuccess { update { copy(status = AssistantStatus.RECORDING, error = null) } }
            .onFailure(::showError)
    }

    fun stopRecordingAndAsk() {
        viewModelScope.launch {
            val audio = runCatching { recorder.stop() }.getOrElse { showError(it); return@launch }
            ask("음성 질문", audioBytes = audio)
        }
    }

    fun cancelRecording() {
        recorder.cancel()
        update { copy(status = AssistantStatus.IDLE) }
    }

    fun requestScene(mode: SceneMode) = update { copy(pendingSceneMode = mode, status = AssistantStatus.CAPTURING, error = null) }

    fun captureScenePhoto() {
        val mode = state.value.pendingSceneMode ?: return
        viewModelScope.launch {
            val image = runCatching { glasses.capturePhoto() }.getOrElse { showError(it); return@launch }
            handleScene(mode, image)
        }
    }

    fun confirmPendingAction() {
        val action = state.value.pendingAction ?: return
        update { copy(pendingAction = null) }
        viewModelScope.launch { applyAssistantResult(action) }
    }

    fun addMemory(title: String, body: String, category: MemoryCategory = MemoryCategory.GENERAL) {
        if (title.isBlank() || body.isBlank()) return
        viewModelScope.launch {
            val currentLocation = locationIfAvailable()
            repository.createMemory(title, body, category, location = currentLocation)
        }
    }

    fun updateMemory(item: MemoryEntity, title: String, body: String, category: MemoryCategory, tags: List<String>) {
        viewModelScope.launch {
            repository.updateMemory(item.copy(title = title.trim(), body = body.trim(), category = category, tagsJson = normalizedTagsJson(tags)))
        }
    }

    fun deleteMemory(item: MemoryEntity) {
        viewModelScope.launch {
            photoStore.deleteMemoryPhoto(item.photoFilename)
            repository.deleteMemory(item)
        }
    }

    fun clearMemories() = viewModelScope.launch { repository.clearMemories() }

    fun addSchedule(title: String, scheduledAt: Long, note: String?) {
        if (title.isBlank()) return
        viewModelScope.launch {
            val item = repository.createSchedule(title, scheduledAt, note, locationIfAvailable())
            LumiNotifications.scheduleSchedule(getApplication(), item)
            warnIfExactAlarmsAreUnavailable()
        }
    }

    fun updateSchedule(item: ScheduleEntity, title: String, scheduledAt: Long, note: String?) {
        viewModelScope.launch {
            val updated = item.copy(title = title.trim(), scheduledAt = scheduledAt, note = note?.trim()?.ifBlank { null })
            repository.updateSchedule(updated)
            LumiNotifications.scheduleSchedule(getApplication(), updated)
        }
    }

    fun deleteSchedule(item: ScheduleEntity) {
        viewModelScope.launch {
            LumiNotifications.cancelSchedule(getApplication(), item.id)
            repository.deleteSchedule(item)
        }
    }

    fun pauseTimer(item: TimerEntity) = viewModelScope.launch {
        repository.pauseTimer(item.id)?.let { LumiNotifications.scheduleTimer(getApplication(), it) }
    }

    fun resumeTimer(item: TimerEntity) = viewModelScope.launch {
        repository.resumeTimer(item.id)?.let { LumiNotifications.scheduleTimer(getApplication(), it) }
    }

    fun deleteTimer(item: TimerEntity) = viewModelScope.launch {
        LumiNotifications.cancelTimer(getApplication(), item.id)
        repository.deleteTimer(item)
    }

    private suspend fun ask(prompt: String, audioBytes: ByteArray? = null, imageBytes: ByteArray? = null, photoFilename: String? = null) {
        update { copy(status = AssistantStatus.THINKING, error = null) }
        val conversation = ensureConversation()
        repository.addMessage(conversation.id, MessageRole.USER, prompt, photoFilename = photoFilename)
        val current = state.value
        val result = runCatching {
            gemini.answer(
                userPrompt = prompt,
                conversation = current.conversations.firstOrNull { it.conversation.id == conversation.id },
                memories = current.memories,
                schedules = current.schedules,
                tone = current.preferences.responseTone,
                audioBytes = audioBytes,
                imageBytes = imageBytes,
            )
        }.getOrElse { showError(it); return }
        if (requiresConfirmation(result) && current.preferences.confirmBeforeAction) {
            update { copy(status = AssistantStatus.IDLE, pendingAction = result) }
        } else {
            applyAssistantResult(result)
        }
    }

    private suspend fun applyAssistantResult(result: AssistantResult) {
        when (result.action) {
            AssistantAction.CAPTURE_SCENE -> {
                requestScene(SceneMode.DESCRIBE)
                return
            }
            AssistantAction.SAVE_PLACE -> {
                requestScene(SceneMode.SAVE_PLACE)
                return
            }
            AssistantAction.SAVE_PARKING -> {
                requestScene(SceneMode.SAVE_PARKING)
                return
            }
            AssistantAction.WEATHER -> {
                val answer = runCatching { weather.answer(requireLocation(), result.weather) }.getOrElse { showError(it); return }
                appendAssistant(answer, result.memoryReferenceIds)
            }
            AssistantAction.CREATE_SCHEDULE -> {
                val draft = result.schedule ?: run { appendAssistant("일정 시각을 다시 알려주세요."); return }
                val scheduledAt = draft.scheduledAt ?: run { appendAssistant("일정 시각을 다시 알려주세요."); return }
                val item = repository.createSchedule(draft.title.ifBlank { "Lumi 일정" }, scheduledAt, draft.note, locationIfAvailable())
                LumiNotifications.scheduleSchedule(getApplication(), item)
                warnIfExactAlarmsAreUnavailable()
                appendAssistant(result.answer.ifBlank { "${item.title} 일정을 등록했어요." })
            }
            AssistantAction.START_TIMER -> {
                val draft = result.timer ?: run { appendAssistant("타이머 시간을 다시 알려주세요."); return }
                val item = repository.createTimer(draft.title.ifBlank { "Lumi 타이머" }, draft.durationSeconds)
                LumiNotifications.scheduleTimer(getApplication(), item)
                warnIfExactAlarmsAreUnavailable()
                appendAssistant(result.answer.ifBlank { "${item.title} 타이머를 시작했어요." })
            }
            AssistantAction.UPDATE_USER_MEMORY -> {
                val draft = result.memoryUpdate ?: run { appendAssistant("수정할 메모를 찾지 못했어요."); return }
                val old = repository.memory(draft.id) ?: run { appendAssistant("수정할 메모를 찾지 못했어요."); return }
                repository.updateMemory(old.copy(title = draft.title, body = draft.body, category = draft.category, tagsJson = normalizedTagsJson(draft.tags)))
                appendAssistant(result.answer.ifBlank { "메모를 수정했어요." })
            }
            AssistantAction.DELETE_USER_MEMORY -> {
                val memory = result.memoryDeletionId?.let(repository::memory) ?: run { appendAssistant("삭제할 메모를 찾지 못했어요."); return }
                photoStore.deleteMemoryPhoto(memory.photoFilename)
                repository.deleteMemory(memory)
                appendAssistant(result.answer.ifBlank { "메모를 삭제했어요." })
            }
            AssistantAction.CURRENT_TIME -> appendAssistant(result.answer.ifBlank { "현재 시간은 ${ZonedDateTime.now().format(DateTimeFormatter.ofPattern("a h시 m분"))}이에요." })
            AssistantAction.ANSWER -> {
                if (result.shouldSaveMemory && result.memory != null) {
                    saveMemoryDraft(result, null, null)
                }
                appendAssistant(result.answer.ifBlank { if (result.shouldSaveMemory) "기억해둘게요." else "다시 한 번 말씀해 주세요." }, result.memoryReferenceIds)
            }
        }
        update { copy(status = AssistantStatus.IDLE, pendingSceneMode = null) }
    }

    private suspend fun handleScene(mode: SceneMode, image: ByteArray) {
        val prompt = when (mode) {
            SceneMode.DESCRIBE -> "현재 보는 장면을 짧고 구체적으로 설명해줘."
            SceneMode.TRANSLATE -> "사진 속 읽을 수 있는 텍스트를 한국어로 자연스럽게 번역해줘."
            SceneMode.SAVE_PLACE -> "현재 장소를 기억하기 좋게 제목, 내용, 태그와 사진 설명을 만들어줘."
            SceneMode.SAVE_PARKING -> "현재 주차 위치를 기억하기 좋게 제목, 내용, 태그와 사진 설명을 만들어줘."
        }
        val conversationPhoto = photoStore.saveConversationPhoto(image)
        if (mode == SceneMode.SAVE_PLACE || mode == SceneMode.SAVE_PARKING) {
            val response = runCatching {
                gemini.answer(prompt, state.value.activeConversation, state.value.memories, state.value.schedules, state.value.preferences.responseTone, imageBytes = image)
            }.getOrElse { showError(it); return }
            val draft = response.memory
            val category = if (mode == SceneMode.SAVE_PARKING) MemoryCategory.PARKING else MemoryCategory.PLACE
            val memoryPhoto = photoStore.saveMemoryPhoto(image)
            val sceneLocation = runCatching { requireLocation() }.getOrElse { showError(it); return }
            repository.createMemory(
                title = draft?.title ?: if (category == MemoryCategory.PARKING) "주차 위치" else "저장한 장소",
                body = draft?.body ?: "안경으로 촬영한 현재 위치예요.",
                category = category,
                photoFilename = memoryPhoto,
                location = sceneLocation,
                tagsJson = normalizedTagsJson(draft?.tags.orEmpty()),
                visualSummary = draft?.visualSummary,
            )
            photoStore.deleteConversationPhoto(conversationPhoto)
            appendAssistant(if (category == MemoryCategory.PARKING) "주차 위치를 기억했어요." else "현재 장소를 기억했어요.")
            update { copy(status = AssistantStatus.IDLE, pendingSceneMode = null) }
            return
        }
        ask(prompt, imageBytes = image, photoFilename = conversationPhoto)
    }

    private suspend fun saveMemoryDraft(result: AssistantResult, photoFilename: String?, image: ByteArray?) {
        val draft = result.memory ?: return
        repository.createMemory(
            title = draft.title,
            body = draft.body,
            category = draft.category,
            photoFilename = photoFilename,
            location = locationIfAvailable(),
            tagsJson = normalizedTagsJson(draft.tags),
            visualSummary = draft.visualSummary,
        )
    }

    private suspend fun appendAssistant(text: String, references: List<String> = emptyList()) {
        val conversation = ensureConversation()
        repository.addMessage(conversation.id, MessageRole.ASSISTANT, text, memoryReferenceIds = references)
        val speech = runCatching { gemini.synthesizeSpeech(text, state.value.preferences.responseTone) }.getOrNull()
        if (speech == null) {
            update { copy(lastAnswer = text, status = AssistantStatus.IDLE) }
            return
        }
        speechPlayer.play(speech)
        update { copy(lastAnswer = text, status = AssistantStatus.SPEAKING) }
        val durationMillis = (speech.bytes.size.toLong() * 1_000L / (speech.sampleRate * speech.channelCount.coerceAtLeast(1) * 2)).coerceAtLeast(500L)
        viewModelScope.launch {
            delay(durationMillis)
            speechPlayer.stop()
            if (state.value.status == AssistantStatus.SPEAKING) update { copy(status = AssistantStatus.IDLE) }
        }
    }

    private suspend fun ensureConversation(): ConversationEntity {
        val id = state.value.selectedConversationId
        val existing = id?.let { repository.conversations.first().firstOrNull { item -> item.conversation.id == it }?.conversation }
        return existing ?: repository.newConversation().also { update { copy(selectedConversationId = it.id) } }
    }

    private suspend fun locationIfAvailable() = if (location.hasPermission()) runCatching { location.currentLocation() }.getOrNull() else null
    private suspend fun requireLocation() = location.currentLocation()

    private fun requiresConfirmation(result: AssistantResult): Boolean = result.shouldSaveMemory || result.action in setOf(
        AssistantAction.SAVE_PLACE,
        AssistantAction.SAVE_PARKING,
        AssistantAction.CREATE_SCHEDULE,
        AssistantAction.START_TIMER,
        AssistantAction.UPDATE_USER_MEMORY,
        AssistantAction.DELETE_USER_MEMORY,
    )

    private fun normalizedTagsJson(tags: List<String>): String {
        val normalized = tags.asSequence()
            .map { it.trim().trim('#').replace(" ", "") }
            .filter(String::isNotBlank)
            .distinctBy { it.lowercase() }
            .take(8)
            .map { it.take(24) }
            .toList()
        return JSONArray(normalized).toString()
    }

    private fun warnIfExactAlarmsAreUnavailable() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !getApplication<Application>().getSystemService(AlarmManager::class.java).canScheduleExactAlarms()) {
            update { copy(error = "정확한 알람 권한이 없어 일정과 타이머 알림이 다소 지연될 수 있어요.") }
        }
    }

    private fun showError(error: Throwable) = update { copy(status = AssistantStatus.IDLE, pendingSceneMode = null, error = error.message ?: "알 수 없는 오류가 발생했어요.") }
    private fun update(transform: LumiUiState.() -> LumiUiState) = _state.update(transform)

    override fun onCleared() {
        recorder.cancel()
        speechPlayer.stop()
        glasses.stop()
        super.onCleared()
    }
}

package com.kotlinsun.lumiandroid.data

import androidx.room.withTransaction
import java.util.UUID
import kotlinx.coroutines.flow.Flow

class LumiRepository(private val database: LumiDatabase) {
    val conversations: Flow<List<ConversationWithMessages>> = database.conversations().observeAll()
    val memories: Flow<List<MemoryEntity>> = database.memories().observeAll()
    val schedules: Flow<List<ScheduleEntity>> = database.schedules().observeAll()
    val timers: Flow<List<TimerEntity>> = database.timers().observeAll()

    suspend fun newConversation(): ConversationEntity = ConversationEntity().also {
        database.conversations().insert(it)
    }

    suspend fun addMessage(
        conversationId: String,
        role: MessageRole,
        text: String,
        photoFilename: String? = null,
        memoryReferenceIds: List<String> = emptyList(),
    ): MessageEntity = database.withTransaction {
        val message = MessageEntity(
            conversationId = conversationId,
            role = role,
            text = text.trim(),
            photoFilename = photoFilename,
        )
        database.conversations().insertMessage(message)
        database.messageMemoryReferences().insertAll(
            memoryReferenceIds.distinct().map { MessageMemoryReferenceEntity(message.id, it) },
        )
        val conversation = database.conversations().find(conversationId)
        val title = if (conversation?.title == "새 대화" && role == MessageRole.USER) {
            text.trim().take(28).ifBlank { "새 대화" }
        } else {
            conversation?.title ?: "새 대화"
        }
        database.conversations().touch(conversationId, title, System.currentTimeMillis())
        message
    }

    suspend fun createMemory(
        title: String,
        body: String,
        category: MemoryCategory = MemoryCategory.GENERAL,
        photoFilename: String? = null,
        location: MemoryLocation? = null,
        tagsJson: String = "[]",
        visualSummary: String? = null,
    ): MemoryEntity = database.withTransaction {
        if (category == MemoryCategory.PARKING) database.memories().deleteParking()
        MemoryEntity(
            title = title.trim(),
            body = body.trim(),
            category = category,
            photoFilename = photoFilename,
            latitude = location?.latitude,
            longitude = location?.longitude,
            address = location?.address,
            tagsJson = tagsJson,
            visualSummary = visualSummary?.trim()?.ifBlank { null },
        ).also(database.memories()::insert)
    }

    suspend fun updateMemory(item: MemoryEntity) = database.memories().update(item)
    suspend fun deleteMemory(item: MemoryEntity) = database.memories().delete(item)
    suspend fun clearMemories() = database.memories().deleteAll()
    suspend fun memory(id: String): MemoryEntity? = database.memories().find(id)
    suspend fun memories(ids: List<String>): List<MemoryEntity> = if (ids.isEmpty()) emptyList() else database.memories().findByIds(ids)
    suspend fun memoryReferenceIds(messageId: String): List<String> = database.messageMemoryReferences().memoryIdsForMessage(messageId)

    suspend fun createSchedule(
        title: String,
        scheduledAt: Long,
        note: String? = null,
        location: MemoryLocation? = null,
    ): ScheduleEntity = ScheduleEntity(
        title = title.trim(),
        scheduledAt = scheduledAt,
        note = note?.trim()?.ifBlank { null },
        latitude = location?.latitude,
        longitude = location?.longitude,
        address = location?.address,
    ).also(database.schedules()::insert)

    suspend fun updateSchedule(item: ScheduleEntity) = database.schedules().update(item)
    suspend fun deleteSchedule(item: ScheduleEntity) = database.schedules().delete(item)
    suspend fun schedule(id: String): ScheduleEntity? = database.schedules().find(id)

    suspend fun createTimer(title: String, durationSeconds: Int): TimerEntity {
        val timer = TimerEntity(
            id = UUID.randomUUID().toString(),
            title = title.trim(),
            endsAt = System.currentTimeMillis() + durationSeconds.coerceIn(1, 604_800) * 1_000L,
        )
        database.timers().insert(timer)
        return timer
    }

    suspend fun pauseTimer(id: String): TimerEntity? = database.withTransaction {
        val timer = database.timers().find(id) ?: return@withTransaction null
        timer.copy(pausedRemainingSeconds = timer.remainingSeconds()).also(database.timers()::update)
    }

    suspend fun resumeTimer(id: String): TimerEntity? = database.withTransaction {
        val timer = database.timers().find(id) ?: return@withTransaction null
        val remaining = timer.pausedRemainingSeconds ?: return@withTransaction timer
        timer.copy(
            startedAt = System.currentTimeMillis(),
            endsAt = System.currentTimeMillis() + remaining * 1_000L,
            pausedRemainingSeconds = null,
        ).also(database.timers()::update)
    }

    suspend fun deleteTimer(item: TimerEntity) = database.timers().delete(item)
    suspend fun timer(id: String): TimerEntity? = database.timers().find(id)
}

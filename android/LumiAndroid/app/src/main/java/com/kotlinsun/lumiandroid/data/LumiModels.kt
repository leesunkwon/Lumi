package com.kotlinsun.lumiandroid.data

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import androidx.room.Relation
import java.util.UUID

enum class MessageRole { USER, ASSISTANT }

enum class MemoryCategory(val title: String) {
    GENERAL("일반"),
    PARKING("주차 기억"),
    PLACE("장소"),
}

enum class ResponseTone(val title: String, val instruction: String, val speechDirection: String) {
    CONCISE("간결함", "답변 톤은 간결함입니다. 결론부터 한두 문장으로 답하세요.", "Keep the delivery crisp and brief."),
    DETAILED("자세한 설명", "답변 톤은 자세한 설명입니다. 결론 뒤에 근거와 다음 행동을 짧게 덧붙이세요.", "Use an explanatory, unhurried pace."),
    JARVIS("친근한 자비스", "답변 톤은 친근한 자비스입니다. 차분하고 따뜻한 개인 비서처럼 답하세요.", "Sound warm, composed, and conversational."),
    WORK("업무 중심", "답변 톤은 업무 중심입니다. 결론, 일정, 할 일을 우선해 분명히 답하세요.", "Sound focused, clear, and professional."),
}

data class MemoryLocation(
    val latitude: Double,
    val longitude: Double,
    val address: String?,
) {
    val displayName: String
        get() = address ?: "위도 %.5f, 경도 %.5f".format(latitude, longitude)
}

@Entity(tableName = "conversations")
data class ConversationEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String = "새 대화",
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis(),
)

@Entity(
    tableName = "messages",
    foreignKeys = [ForeignKey(
        entity = ConversationEntity::class,
        parentColumns = ["id"],
        childColumns = ["conversationId"],
        onDelete = ForeignKey.CASCADE,
    )],
    indices = [Index("conversationId")],
)
data class MessageEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val conversationId: String,
    val role: MessageRole,
    val text: String,
    val photoFilename: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
)

@Entity(tableName = "memories")
data class MemoryEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String,
    val body: String,
    val category: MemoryCategory = MemoryCategory.GENERAL,
    val photoFilename: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val address: String? = null,
    val tagsJson: String = "[]",
    val visualSummary: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val location: MemoryLocation?
        get() = if (latitude != null && longitude != null) MemoryLocation(latitude, longitude, address) else null
}

@Entity(tableName = "schedules")
data class ScheduleEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String,
    val scheduledAt: Long,
    val note: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val address: String? = null,
    val createdAt: Long = System.currentTimeMillis(),
) {
    val location: MemoryLocation?
        get() = if (latitude != null && longitude != null) MemoryLocation(latitude, longitude, address) else null
}

@Entity(tableName = "timers")
data class TimerEntity(
    @PrimaryKey val id: String = UUID.randomUUID().toString(),
    val title: String,
    val startedAt: Long = System.currentTimeMillis(),
    val endsAt: Long,
    val pausedRemainingSeconds: Int? = null,
) {
    fun remainingSeconds(now: Long = System.currentTimeMillis()): Int =
        pausedRemainingSeconds ?: ((endsAt - now + 999L) / 1000L).coerceAtLeast(0).toInt()

    val isPaused: Boolean get() = pausedRemainingSeconds != null
}

@Entity(
    tableName = "message_memory_references",
    primaryKeys = ["messageId", "memoryId"],
    foreignKeys = [
        ForeignKey(entity = MessageEntity::class, parentColumns = ["id"], childColumns = ["messageId"], onDelete = ForeignKey.CASCADE),
        ForeignKey(entity = MemoryEntity::class, parentColumns = ["id"], childColumns = ["memoryId"], onDelete = ForeignKey.CASCADE),
    ],
    indices = [Index("memoryId")],
)
data class MessageMemoryReferenceEntity(
    val messageId: String,
    val memoryId: String,
)

data class ConversationWithMessages(
    @androidx.room.Embedded val conversation: ConversationEntity,
    @Relation(parentColumn = "id", entityColumn = "conversationId") val messages: List<MessageEntity>,
)

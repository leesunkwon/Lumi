package com.kotlinsun.lumiandroid.data

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.Transaction
import androidx.room.TypeConverter
import androidx.room.TypeConverters
import androidx.room.Update
import kotlinx.coroutines.flow.Flow

class LumiConverters {
    @TypeConverter fun messageRoleToString(value: MessageRole): String = value.name
    @TypeConverter fun stringToMessageRole(value: String): MessageRole = MessageRole.valueOf(value)
    @TypeConverter fun categoryToString(value: MemoryCategory): String = value.name
    @TypeConverter fun stringToCategory(value: String): MemoryCategory = MemoryCategory.valueOf(value)
}

@Dao
interface ConversationDao {
    @Transaction
    @Query("SELECT * FROM conversations ORDER BY updatedAt DESC")
    fun observeAll(): Flow<List<ConversationWithMessages>>

    @Query("SELECT * FROM conversations WHERE id = :id LIMIT 1")
    suspend fun find(id: String): ConversationEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: ConversationEntity)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertMessage(item: MessageEntity)

    @Query("UPDATE conversations SET updatedAt = :updatedAt, title = :title WHERE id = :conversationId")
    suspend fun touch(conversationId: String, title: String, updatedAt: Long)

    @Delete
    suspend fun delete(item: ConversationEntity)
}

@Dao
interface MemoryDao {
    @Query("SELECT * FROM memories ORDER BY createdAt DESC")
    fun observeAll(): Flow<List<MemoryEntity>>

    @Query("SELECT * FROM memories WHERE id IN (:ids)")
    suspend fun findByIds(ids: List<String>): List<MemoryEntity>

    @Query("SELECT * FROM memories WHERE id = :id LIMIT 1")
    suspend fun find(id: String): MemoryEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: MemoryEntity)

    @Update
    suspend fun update(item: MemoryEntity)

    @Delete
    suspend fun delete(item: MemoryEntity)

    @Query("DELETE FROM memories WHERE category = 'PARKING'")
    suspend fun deleteParking()

    @Query("DELETE FROM memories")
    suspend fun deleteAll()
}

@Dao
interface ScheduleDao {
    @Query("SELECT * FROM schedules ORDER BY scheduledAt ASC")
    fun observeAll(): Flow<List<ScheduleEntity>>

    @Query("SELECT * FROM schedules WHERE scheduledAt >= :now ORDER BY scheduledAt ASC")
    fun observeUpcoming(now: Long): Flow<List<ScheduleEntity>>

    @Query("SELECT * FROM schedules WHERE id = :id LIMIT 1")
    suspend fun find(id: String): ScheduleEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: ScheduleEntity)

    @Update
    suspend fun update(item: ScheduleEntity)

    @Delete
    suspend fun delete(item: ScheduleEntity)
}

@Dao
interface TimerDao {
    @Query("SELECT * FROM timers ORDER BY endsAt ASC")
    fun observeAll(): Flow<List<TimerEntity>>

    @Query("SELECT * FROM timers WHERE id = :id LIMIT 1")
    suspend fun find(id: String): TimerEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(item: TimerEntity)

    @Update
    suspend fun update(item: TimerEntity)

    @Delete
    suspend fun delete(item: TimerEntity)
}

@Dao
interface MessageMemoryReferenceDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(items: List<MessageMemoryReferenceEntity>)

    @Query("SELECT memoryId FROM message_memory_references WHERE messageId = :messageId")
    suspend fun memoryIdsForMessage(messageId: String): List<String>
}

@Database(
    entities = [
        ConversationEntity::class,
        MessageEntity::class,
        MemoryEntity::class,
        ScheduleEntity::class,
        TimerEntity::class,
        MessageMemoryReferenceEntity::class,
    ],
    version = 1,
    exportSchema = false,
)
@TypeConverters(LumiConverters::class)
abstract class LumiDatabase : RoomDatabase() {
    abstract fun conversations(): ConversationDao
    abstract fun memories(): MemoryDao
    abstract fun schedules(): ScheduleDao
    abstract fun timers(): TimerDao
    abstract fun messageMemoryReferences(): MessageMemoryReferenceDao

    companion object {
        fun create(context: Context): LumiDatabase = Room.databaseBuilder(
            context.applicationContext,
            LumiDatabase::class.java,
            "lumi.db",
        ).fallbackToDestructiveMigration().build()
    }
}

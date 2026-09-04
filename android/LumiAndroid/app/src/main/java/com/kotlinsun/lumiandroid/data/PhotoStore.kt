package com.kotlinsun.lumiandroid.data

import android.content.Context
import java.io.File
import java.util.UUID

class PhotoStore(private val context: Context) {
    private val conversationsDir: File get() = File(context.filesDir, "conversation_photos").apply { mkdirs() }
    private val memoriesDir: File get() = File(context.filesDir, "memory_photos").apply { mkdirs() }

    fun saveConversationPhoto(bytes: ByteArray): String = save(conversationsDir, bytes)
    fun saveMemoryPhoto(bytes: ByteArray): String = save(memoriesDir, bytes)

    fun conversationPhoto(name: String): File = File(conversationsDir, name)
    fun memoryPhoto(name: String): File = File(memoriesDir, name)

    fun deleteConversationPhoto(name: String?) = delete(conversationsDir, name)
    fun deleteMemoryPhoto(name: String?) = delete(memoriesDir, name)

    private fun save(directory: File, bytes: ByteArray): String {
        val filename = "${UUID.randomUUID()}.jpg"
        File(directory, filename).writeBytes(bytes)
        return filename
    }

    private fun delete(directory: File, name: String?) {
        if (!name.isNullOrBlank()) File(directory, name).delete()
    }
}

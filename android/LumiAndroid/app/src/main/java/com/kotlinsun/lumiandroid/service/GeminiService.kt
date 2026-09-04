package com.kotlinsun.lumiandroid.service

import com.kotlinsun.lumiandroid.BuildConfig
import com.kotlinsun.lumiandroid.data.ConversationWithMessages
import com.kotlinsun.lumiandroid.data.MemoryEntity
import com.kotlinsun.lumiandroid.data.MemoryCategory
import com.kotlinsun.lumiandroid.data.ResponseTone
import com.kotlinsun.lumiandroid.data.ScheduleEntity
import java.io.BufferedReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.time.OffsetDateTime
import java.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

class GeminiService {
    suspend fun answer(
        userPrompt: String,
        conversation: ConversationWithMessages?,
        memories: List<MemoryEntity>,
        schedules: List<ScheduleEntity>,
        tone: ResponseTone,
        audioBytes: ByteArray? = null,
        imageBytes: ByteArray? = null,
    ): AssistantResult = withContext(Dispatchers.IO) {
        val apiKey = requireApiKey()
        val systemPrompt = buildSystemPrompt(conversation, memories, schedules, tone)
        val parts = JSONArray().put(JSONObject().put("text", userPrompt))
        audioBytes?.let {
            parts.put(inlineData("audio/mp4", it))
        }
        imageBytes?.let {
            parts.put(inlineData("image/jpeg", it))
        }
        val body = JSONObject()
            .put("systemInstruction", JSONObject().put("parts", JSONArray().put(JSONObject().put("text", systemPrompt))))
            .put("contents", JSONArray().put(JSONObject().put("role", "user").put("parts", parts)))
            .put("generationConfig", JSONObject().put("temperature", 0.2).put("responseMimeType", "application/json"))

        val response = postJson(
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite:generateContent?key=${apiKey.urlEncoded()}",
            body,
        )
        val rawText = response.optJSONArray("candidates")
            ?.optJSONObject(0)
            ?.optJSONObject("content")
            ?.optJSONArray("parts")
            ?.let { partsArray -> buildString { for (index in 0 until partsArray.length()) append(partsArray.optJSONObject(index)?.optString("text").orEmpty()) } }
            ?.trim()
            ?.removePrefix("```json")
            ?.removePrefix("```")
            ?.removeSuffix("```")
            ?.trim()
            .orEmpty()
        if (rawText.isBlank()) throw GeminiServiceException("Gemini에서 응답을 받지 못했어요.")
        parseAssistantResult(rawText)
    }

    suspend fun synthesizeSpeech(text: String, tone: ResponseTone): SynthesizedSpeech = withContext(Dispatchers.IO) {
        val apiKey = requireApiKey()
        val transcript = text.replace("</transcript>", "").trim()
        if (transcript.isBlank()) throw GeminiServiceException("재생할 답변이 없어요.")
        val prompt = """
            # AUDIO PROFILE
            Lumi is a warm, composed, trustworthy Korean personal assistant.
            Speak in natural standard Korean. ${tone.speechDirection}
            Read only the text inside the transcript tags.
            <transcript>
            $transcript
            </transcript>
        """.trimIndent()
        val body = JSONObject()
            .put("model", "gemini-3.1-flash-tts-preview")
            .put("input", prompt)
            .put("responseFormat", JSONObject().put("type", "audio"))
            .put("generationConfig", JSONObject().put("speechConfig", JSONArray().put(JSONObject().put("voice", "Kore"))))
        val response = postJson(
            "https://generativelanguage.googleapis.com/v1beta/interactions",
            body,
            mapOf("x-goog-api-key" to apiKey),
        )
        val steps = response.optJSONArray("steps") ?: throw GeminiServiceException("음성 응답 형식이 올바르지 않아요.")
        for (stepIndex in 0 until steps.length()) {
            val content = steps.optJSONObject(stepIndex)?.optJSONArray("content") ?: continue
            for (contentIndex in 0 until content.length()) {
                val item = content.optJSONObject(contentIndex) ?: continue
                if (item.optString("type") == "audio" && item.optString("data").isNotBlank()) {
                    return@withContext SynthesizedSpeech(
                        bytes = Base64.getDecoder().decode(item.getString("data")),
                        sampleRate = item.optInt("sampleRate", 24_000),
                        channelCount = item.optInt("channels", 1),
                    )
                }
            }
        }
        throw GeminiServiceException("재생 가능한 음성 응답을 받지 못했어요.")
    }

    private fun buildSystemPrompt(
        conversation: ConversationWithMessages?,
        memories: List<MemoryEntity>,
        schedules: List<ScheduleEntity>,
        tone: ResponseTone,
    ): String = """
        당신은 Lumi, Ray-Ban Meta와 함께 동작하는 개인 AI 비서입니다.
        답변은 음성으로 듣기 자연스러운 짧은 한국어 구어체로 작성하고 Markdown, URL, 이모지를 사용하지 마세요.
        ${tone.instruction}

        현재 시간: ${java.time.ZonedDateTime.now(java.time.ZoneId.of("Asia/Seoul"))}
        대화 기록: ${conversation?.messages?.takeLast(20)?.joinToString("\n") { "${it.role}: ${it.text}" }.orEmpty()}
        사용자 메모리: ${memories.joinToString("\n") { "id=${it.id}, 분류=${it.category}, 제목=${it.title}, 내용=${it.body}, 장소=${it.address ?: "미기록"}, 태그=${it.tagsJson}" }}
        다가오는 일정: ${schedules.filter { it.scheduledAt > System.currentTimeMillis() }.joinToString("\n") { "id=${it.id}, 제목=${it.title}, 시각=${java.time.Instant.ofEpochMilli(it.scheduledAt)}, 메모=${it.note.orEmpty()}" }}

        반드시 아래 JSON만 반환하세요.
        {
          "transcript":"사용자 입력 전사 또는 텍스트",
          "answer":"사용자에게 들려줄 답변",
          "action":"answer|capture_scene|current_time|weather|save_place|save_parking|create_schedule|start_timer|update_user_memory|delete_user_memory",
          "shouldSaveUserMemory":false,
          "userMemory":{"title":"", "body":"", "category":"general|parking|place", "tags":[], "visualSummary":null},
          "userMemoryUpdate":{"memoryID":"", "title":"", "body":"", "category":"general|parking|place", "tags":[]},
          "userMemoryDeletion":{"memoryID":""},
          "memoryReferenceIDs":[],
          "weatherDetail":{"day":"today|tomorrow", "period":"current|morning|afternoon|evening|night|day"},
          "scheduleDetail":{"title":"", "scheduledAt":"yyyy-MM-dd'T'HH:mm:ssXXX", "note":""},
          "timerDetail":{"title":"", "durationSeconds":480}
        }
        저장은 사용자가 기억, 메모, 기록을 명시적으로 요청했을 때만 shouldSaveUserMemory를 true로 설정하세요.
        미래 일정은 create_schedule, 상대 시간 타이머는 start_timer를 사용하세요. 대상이 불명확한 수정·삭제는 실행하지 말고 짧게 되물으세요.
    """.trimIndent()

    private fun parseAssistantResult(text: String): AssistantResult {
        val payload = try {
            JSONObject(text)
        } catch (_: Exception) {
            return AssistantResult(answer = text, transcript = null)
        }
        val action = AssistantAction.from(payload.optString("action"))
        val memory = payload.optJSONObject("userMemory")?.let(::parseMemoryDraft)
        val update = payload.optJSONObject("userMemoryUpdate")?.let(::parseMemoryUpdate)
        val deletionId = payload.optJSONObject("userMemoryDeletion")?.optString("memoryID")?.takeIf(String::isNotBlank)
        val references = payload.optJSONArray("memoryReferenceIDs").strings().take(5)
        val weather = payload.optJSONObject("weatherDetail")?.let {
            WeatherDetail(it.optString("day", "today"), it.optString("period", "current"))
        }
        val schedule = payload.optJSONObject("scheduleDetail")?.let {
            ScheduleDraft(
                title = it.optString("title").trim(),
                scheduledAt = runCatching { OffsetDateTime.parse(it.optString("scheduledAt")).toInstant().toEpochMilli() }.getOrNull(),
                note = it.optString("note").trim().ifBlank { null },
            )
        }
        val timer = payload.optJSONObject("timerDetail")?.let {
            TimerDraft(it.optString("title").trim(), it.optInt("durationSeconds", 0))
        }
        return AssistantResult(
            transcript = payload.optString("transcript").trim().ifBlank { null },
            answer = payload.optString("answer").trim().ifBlank { if (action == AssistantAction.ANSWER) "다시 한 번 말씀해 주세요." else "" },
            action = action,
            shouldSaveMemory = payload.optBoolean("shouldSaveUserMemory", false),
            memory = memory,
            memoryUpdate = update,
            memoryDeletionId = deletionId,
            memoryReferenceIds = references,
            weather = weather,
            schedule = schedule,
            timer = timer,
        )
    }

    private fun parseMemoryDraft(value: JSONObject): MemoryDraft? {
        val title = value.optString("title").trim()
        val body = value.optString("body").trim()
        if (title.isBlank() || body.isBlank()) return null
        return MemoryDraft(
            title = title,
            body = body,
            category = MemoryCategory.entries.firstOrNull { it.name.equals(value.optString("category"), true) }
                ?: MemoryCategory.GENERAL,
            tags = value.optJSONArray("tags").strings(),
            visualSummary = value.optString("visualSummary").trim().ifBlank { null },
        )
    }

    private fun parseMemoryUpdate(value: JSONObject): MemoryUpdateDraft? {
        val id = value.optString("memoryID").trim()
        val title = value.optString("title").trim()
        val body = value.optString("body").trim()
        if (id.isBlank() || title.isBlank() || body.isBlank()) return null
        return MemoryUpdateDraft(
            id = id,
            title = title,
            body = body,
            category = MemoryCategory.entries.firstOrNull { it.name.equals(value.optString("category"), true) }
                ?: MemoryCategory.GENERAL,
            tags = value.optJSONArray("tags").strings(),
        )
    }

    private fun JSONArray?.strings(): List<String> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) {
                optString(index).trim().takeIf(String::isNotBlank)?.let(::add)
            }
        }
    }

    private fun inlineData(mimeType: String, bytes: ByteArray): JSONObject = JSONObject().put(
        "inlineData",
        JSONObject().put("mimeType", mimeType).put("data", Base64.getEncoder().encodeToString(bytes)),
    )

    private fun postJson(url: String, body: JSONObject, headers: Map<String, String> = emptyMap()): JSONObject {
        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 20_000
            readTimeout = 60_000
            doOutput = true
            setRequestProperty("Content-Type", "application/json")
            headers.forEach(::setRequestProperty)
        }
        try {
            OutputStreamWriter(connection.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
            val stream = if (connection.responseCode in 200..299) connection.inputStream else connection.errorStream
            val responseText = stream?.bufferedReader()?.use(BufferedReader::readText).orEmpty()
            if (connection.responseCode !in 200..299) {
                val message = runCatching { JSONObject(responseText).optJSONObject("error")?.optString("message") }.getOrNull()
                throw GeminiServiceException(message?.ifBlank { null } ?: "Gemini 요청에 실패했어요. HTTP ${connection.responseCode}")
            }
            return JSONObject(responseText)
        } finally {
            connection.disconnect()
        }
    }

    private fun requireApiKey(): String = BuildConfig.GEMINI_API_KEY.takeIf(String::isNotBlank)
        ?: throw GeminiServiceException("Gemini API 키가 없습니다. local.properties에 GEMINI_API_KEY를 설정해주세요.")

    private fun String.urlEncoded(): String = java.net.URLEncoder.encode(this, Charsets.UTF_8.name())
}

class GeminiServiceException(message: String) : IllegalStateException(message)

enum class AssistantAction {
    ANSWER, CAPTURE_SCENE, CURRENT_TIME, WEATHER, SAVE_PLACE, SAVE_PARKING, CREATE_SCHEDULE, START_TIMER, UPDATE_USER_MEMORY, DELETE_USER_MEMORY;

    companion object {
        fun from(value: String): AssistantAction = entries.firstOrNull { it.name.equals(value.replace('-', '_'), true) } ?: ANSWER
    }
}

data class AssistantResult(
    val transcript: String?,
    val answer: String,
    val action: AssistantAction = AssistantAction.ANSWER,
    val shouldSaveMemory: Boolean = false,
    val memory: MemoryDraft? = null,
    val memoryUpdate: MemoryUpdateDraft? = null,
    val memoryDeletionId: String? = null,
    val memoryReferenceIds: List<String> = emptyList(),
    val weather: WeatherDetail? = null,
    val schedule: ScheduleDraft? = null,
    val timer: TimerDraft? = null,
)

data class MemoryDraft(val title: String, val body: String, val category: MemoryCategory, val tags: List<String>, val visualSummary: String?)
data class MemoryUpdateDraft(val id: String, val title: String, val body: String, val category: MemoryCategory, val tags: List<String>)
data class WeatherDetail(val day: String, val period: String)
data class ScheduleDraft(val title: String, val scheduledAt: Long?, val note: String?)
data class TimerDraft(val title: String, val durationSeconds: Int)
data class SynthesizedSpeech(val bytes: ByteArray, val sampleRate: Int, val channelCount: Int)

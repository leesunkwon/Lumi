//
//  GeminiService.swift
//  MetaGemini
//

import Foundation

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case invalidSpeechResponse
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API 키가 없습니다. Secrets.xcconfig에 GEMINI_API_KEY를 설정해주세요."
        case .invalidResponse:
            return "Gemini에서 이해할 수 없는 응답을 받았습니다."
        case .invalidSpeechResponse:
            return "Gemini 음성 응답을 재생 가능한 형식으로 받지 못했습니다."
        case .serviceError(let message):
            return "Gemini 요청에 실패했습니다: \(message)"
        }
    }
}

struct AssistantResult {
    let transcript: String?
    let answer: String
    let userMemory: UserMemoryDraft?
    let shouldSaveUserMemory: Bool
    let action: AssistantAction
    let timeDetail: TimeDetail?
}

enum AssistantAction: String, Decodable {
    case answer
    case captureScene = "capture_scene"
    case currentTime = "current_time"
}

enum TimeDetail: String, Decodable {
    case time
    case date
    case dateTime = "date_time"
}

struct SynthesizedSpeech {
    let audioData: Data
    let mimeType: String
    let sampleRate: Int
    let channelCount: Int
}

struct GeminiService {
    private let model = "gemini-3.1-flash-lite"
    private let speechModel = "gemini-3.1-flash-tts-preview"
    private let speechVoice = "Sulafat"

    func answerVoiceQuestion(
        audioURL: URL,
        conversation: ConversationSession?,
        userMemories: [VoiceMemo]
    ) async throws -> AssistantResult {
        let audioData = try Data(contentsOf: audioURL)
        return try await generate(
            instruction: """
            사용자의 음성 질문을 한국어로 정확히 전사하고, 의도에 맞는 다음 행동을 선택하세요.

            action은 반드시 다음 중 하나입니다.
            - capture_scene: 사용자가 지금 보고 있는 물건, 메뉴, 문서, 사람, 주변 장면처럼 새 사진을 찍어야만 답할 수 있는 내용을 분석해 달라고 요청한 경우입니다. transcript에 전체 질문을 넣고 answer는 빈 문자열로 남기세요.
            - current_time: 사용자가 이 iPhone의 현재 시각, 오늘 날짜, 요일을 물어본 경우입니다. 다른 도시·시간대의 시간은 이 동작을 사용하지 마세요. transcript에 전체 질문을 넣고 answer는 빈 문자열로 남기세요. timeDetail에는 time, date, date_time 중 알맞은 값을 넣으세요.
            - answer: 사진이나 현재 시간이 필요하지 않은 모든 요청입니다. transcript에 전체 질문을 넣고 자연스러운 답을 작성하세요.

            단순히 사진이나 시간이라는 단어가 나왔다고 action을 선택하지 마세요. 이전 대화의 사진을 언급하거나 일반적인 사진 관련 질문은 answer로 처리하세요.
            일정, 사용자 메모리, 아이디어 정리 요청에는 간결하고 실용적으로 답하세요.
            사용자 메모리 저장은 사용자가 "이건 기억해줘", "방금 말한 내용을 내 메모리에 저장해줘"처럼
            저장할 대상을 가리키며 명확하게 요청한 경우에만 shouldSaveUserMemory를 true로 설정하세요.
            단순히 기억, 메모, 저장이라는 단어를 언급하거나 기억에 관한 질문을 했다는 이유만으로 저장하지 마세요.
            true인 경우에만 userMemory를 채우고, 대화 문맥에서 저장할 정보만 정확히 추출하세요.
            userMemory.category는 반드시 general, schedule, parking 중 하나로 정하세요.
            - schedule: 약속, 일정, 마감과 사용자가 해야 하는 실행 항목
            - parking: 현재 차량을 주차한 위치나 주차 관련 기억
            - general: 그 외 개인 선호, 사실, 아이디어
            """,
            audioData: audioData,
            imageData: nil,
            conversation: conversation,
            userMemories: userMemories,
            userPrompt: "음성 질문을 전사하고 요청을 처리해 주세요."
        )
    }

    func describeScene(
        question: String = "지금 보는 장면을 설명해줘.",
        imageData: Data,
        conversation: ConversationSession?,
        userMemories: [VoiceMemo]
    ) async throws -> AssistantResult {
        let result = try await generate(
            instruction: """
            사용자가 안경 카메라로 본 장면에 관해 요청했습니다. 사용자의 질문에 맞춰 한국어로 2~3문장 안에서 답하세요. 보이는 물체, 읽을 수 있는 핵심 텍스트,
            사용자가 다음에 취할 수 있는 실용적인 행동을 우선해서 말하세요. 확실하지 않은 정보는 추측이라고 밝혀야 합니다.
            사진은 지금 이 요청을 처리하기 위해 새로 촬영된 것이므로 action은 반드시 answer로 설정하세요.
            사용자 메모리 저장은 사용자가 저장할 대상을 가리키며 명확하게 요청한 경우에만 shouldSaveUserMemory를 true로 설정하세요.
            true인 경우에만 userMemory를 채우고, 대화 문맥에서 저장할 정보만 정확히 추출하세요.
            userMemory.category는 general, schedule, parking 중 하나여야 합니다. 장면에서 파악한 차량 주차 위치는 parking으로 분류하세요.
            """,
            audioData: nil,
            imageData: imageData,
            conversation: conversation,
            userMemories: userMemories,
            userPrompt: "사용자 요청: \(question)"
        )

        return AssistantResult(
            transcript: result.transcript,
            answer: result.answer.isEmpty ? "사진을 분석하지 못했어요. 다시 한 번 시도해 주세요." : result.answer,
            userMemory: result.userMemory,
            shouldSaveUserMemory: result.shouldSaveUserMemory,
            action: .answer,
            timeDetail: nil
        )
    }

    func synthesizeSpeech(_ text: String) async throws -> SynthesizedSpeech {
        let apiKey = try requireAPIKey()
        let transcript = text
            .replacingOccurrences(of: "</transcript>", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            throw GeminiServiceError.invalidSpeechResponse
        }

        let prompt = """
        # AUDIO PROFILE
        Lumi is a warm, composed, and trustworthy personal AI assistant.

        # SCENE
        Lumi is speaking privately to one person through smart-glasses speakers.

        # DIRECTOR'S NOTES
        Speak in natural standard Korean. Sound warm, friendly, and conversational rather than like an announcer.
        Use a relaxed, slightly brisk pace with short natural pauses. Keep the volume and emotion even.
        Pronounce numbers and English words clearly. Do not read these directions or add any words.

        # TRANSCRIPT
        Read only the text inside the transcript tags, verbatim.
        <transcript>
        \(transcript)
        </transcript>
        """

        let requestBody = TTSInteractionRequest(
            model: speechModel,
            input: prompt,
            responseFormat: TTSResponseFormat(type: "audio"),
            generationConfig: TTSGenerationConfig(
                speechConfig: [TTSSpeechConfig(voice: speechVoice)]
            )
        )

        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions") else {
            throw GeminiServiceError.invalidSpeechResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 60
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidSpeechResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data)
            throw GeminiServiceError.serviceError(errorResponse?.error.message ?? "HTTP \(httpResponse.statusCode)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let responseBody = try decoder.decode(TTSInteractionResponse.self, from: data)
        guard responseBody.status == "completed" else {
            throw GeminiServiceError.invalidSpeechResponse
        }

        let audioContent = responseBody.steps?
            .filter { $0.type == "model_output" }
            .compactMap(\.content)
            .flatMap { $0 }
            .first { $0.type == "audio" && $0.data != nil }

        guard let audioContent,
              let encodedAudio = audioContent.data,
              let audioData = Data(base64Encoded: encodedAudio),
              !audioData.isEmpty
        else {
            throw GeminiServiceError.invalidSpeechResponse
        }

        return SynthesizedSpeech(
            audioData: audioData,
            mimeType: audioContent.mimeType ?? "audio/l16",
            sampleRate: audioContent.sampleRate ?? 24_000,
            channelCount: audioContent.channels ?? 1
        )
    }

    private func generate(
        instruction: String,
        audioData: Data?,
        imageData: Data?,
        conversation: ConversationSession?,
        userMemories: [VoiceMemo],
        userPrompt: String
    ) async throws -> AssistantResult {
        let apiKey = try requireAPIKey()
        let conversationContext = formattedConversationContext(conversation)
        let userMemoryContext = formattedUserMemoryContext(userMemories)
        let runtimeContext = currentRuntimeContext()

        let systemPrompt = """
        당신은 Lumi, Ray-Ban Meta와 함께 동작하는 개인 AI 비서입니다.
        \(instruction)

        answer는 음성으로 들었을 때 자연스러운 한국어 구어체로 작성하세요. 짧고 완결된 문장을 사용하고,
        Markdown 기호, URL, 이모지, 표처럼 소리 내어 읽기 어려운 표현은 사용하지 마세요.

        아래는 현재 대화 세션의 시작·최근 갱신 시각과 앞서 나눈 메시지입니다. 현재 질문에 도움이 될 때만 자연스럽게 참고하고,
        메시지 기록 시각은 “아까”, “어제”, “지난주” 같은 상대 시간의 문맥을 해석할 때 현재 시간과 비교해 사용하세요.
        기록 시각을 실제 사건이나 일정의 시각으로 단정하지 말고, 메시지 본문에 적힌 날짜·시간을 우선하세요.
        이전 내용을 이미 알고 있다고 불필요하게 언급하지 마세요.
        <conversation_history>
        \(conversationContext)
        </conversation_history>

        아래는 사용자가 명시적으로 저장한 사용자 메모리입니다. 각 항목의 기록 시각은 메모리를 저장한 시점이며,
        현재 시간과 비교해 “지난주에 기억해 둔 일정”처럼 메모리의 상대적인 기록 시점을 해석할 때 참고하세요.
        기록 시각을 실제 일정이나 사건의 발생 시각으로 단정하지 말고, 메모리 본문에 적힌 날짜·시간을 우선하세요.
        현재 질문과 관련된 항목만 자연스럽게 사용하고, 메모리 목록 전체를 그대로 나열하지 마세요.
        <user_memories>
        \(userMemoryContext)
        </user_memories>

        iPhone에서 읽은 현재 시간입니다. 현재 시각·날짜·요일 관련 질문에서만 이 값을 기준으로 삼으세요.
        <runtime_context>
        \(runtimeContext)
        </runtime_context>

        반드시 아래 JSON만 반환하세요. Markdown 코드 블록을 쓰지 마세요.
        {
          "transcript": "음성 입력의 한국어 전사. 이미지 전용이면 빈 문자열",
          "answer": "사용자에게 들려줄 한국어 답변",
          "shouldSaveUserMemory": true 또는 false,
          "userMemory": { "title": "저장할 주제를 8~20자로 정확히 요약", "body": "사용자가 저장하라고 한 사실·일정·숫자·조건만 1~3문장으로 요약", "category": "general | schedule | parking" } 또는 null,
          "action": "answer | capture_scene | current_time",
          "timeDetail": "time | date | date_time 또는 null"
        }

        shouldSaveUserMemory가 false이면 userMemory는 반드시 null입니다. true이면 사용자가 저장하려는 내용만 남기고,
        추측하거나 빠진 정보를 보완하지 마세요. 저장할 핵심을 판단할 수 없으면 false로 두고 짧은 확인 질문을 하세요.
        """

        var parts = [GeminiPart(text: userPrompt)]
        if let audioData {
            parts.append(GeminiPart(inlineData: InlineData(mimeType: "audio/mp4", data: audioData.base64EncodedString())))
        }
        if let imageData {
            parts.append(GeminiPart(inlineData: InlineData(mimeType: "image/jpeg", data: imageData.base64EncodedString())))
        }

        let requestBody = GeminiRequest(
            systemInstruction: GeminiContent(parts: [GeminiPart(text: systemPrompt)]),
            contents: [GeminiContent(role: "user", parts: parts)],
            generationConfig: GenerationConfig(temperature: 0.2, responseMimeType: "application/json")
        )

        let encodedKey = apiKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? apiKey
        let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(encodedKey)"
        guard let url = URL(string: endpoint) else {
            throw GeminiServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorResponse = try? JSONDecoder().decode(GeminiErrorResponse.self, from: data)
            throw GeminiServiceError.serviceError(errorResponse?.error.message ?? "HTTP \(httpResponse.statusCode)")
        }

        let responseBody = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = responseBody.candidates?
            .first?
            .content?
            .parts?
            .compactMap(\.text)
            .joined()

        guard let text, !text.isEmpty else {
            throw GeminiServiceError.invalidResponse
        }

        let cleanedText = text
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let payload = try? JSONDecoder().decode(AssistantPayload.self, from: Data(cleanedText.utf8)) {
            let action = payload.action ?? .answer
            let answer = payload.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            return AssistantResult(
                transcript: payload.transcript?.nilIfEmpty,
                answer: action == .answer && answer.isEmpty ? "죄송해요. 다시 한 번 말씀해 주세요." : answer,
                userMemory: payload.userMemory,
                shouldSaveUserMemory: payload.shouldSaveUserMemory ?? false,
                action: action,
                timeDetail: payload.timeDetail
            )
        }

        return AssistantResult(
            transcript: nil,
            answer: cleanedText,
            userMemory: nil,
            shouldSaveUserMemory: false,
            action: .answer,
            timeDetail: nil
        )
    }

    private func currentRuntimeContext(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy년 M월 d일 EEEE a h시 mm분"
        return "\(formatter.string(from: date)) (\(TimeZone.current.identifier))"
    }

    private func formattedConversationContext(_ conversation: ConversationSession?) -> String {
        guard let conversation else { return "이전 대화 없음" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy년 M월 d일 EEEE a h시 mm분"

        let sessionTimeline = [
            "세션 시작: \(formatter.string(from: conversation.createdAt))",
            "최근 갱신: \(formatter.string(from: conversation.updatedAt))"
        ]

        let recentMessages = conversation.messages.suffix(10)
        guard !recentMessages.isEmpty else {
            return (sessionTimeline + ["이전 메시지 없음"]).joined(separator: "\n")
        }

        let messages = recentMessages
            .map { message in
                let speaker = message.role == .user ? "사용자" : "Lumi"
                let text = message.text
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .prefix(500)
                return "[기록 시각: \(formatter.string(from: message.createdAt))] \(speaker): \(text)"
            }
            .joined(separator: "\n")

        return (sessionTimeline + [messages]).joined(separator: "\n")
    }

    private func formattedUserMemoryContext(_ memories: [VoiceMemo]) -> String {
        guard !memories.isEmpty else { return "저장된 사용자 메모리 없음" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy년 M월 d일 EEEE a h시 mm분"

        return memories
            .sorted { $0.createdAt > $1.createdAt }
            .map { memory in
                let title = memory.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = memory.body.trimmingCharacters(in: .whitespacesAndNewlines)
                return "[기록 시각: \(formatter.string(from: memory.createdAt))] \(title) — \(body)"
            }
            .joined(separator: "\n")
    }

    private func requireAPIKey() throws -> String {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
              !apiKey.isEmpty,
              !apiKey.contains("$")
        else {
            throw GeminiServiceError.missingAPIKey
        }

        return apiKey
    }
}

private struct GeminiRequest: Encodable {
    let systemInstruction: GeminiContent
    let contents: [GeminiContent]
    let generationConfig: GenerationConfig
}

private struct GeminiContent: Codable {
    let role: String?
    let parts: [GeminiPart]

    init(role: String? = nil, parts: [GeminiPart]) {
        self.role = role
        self.parts = parts
    }
}

private struct GeminiPart: Codable {
    let text: String?
    let inlineData: InlineData?

    init(text: String) {
        self.text = text
        self.inlineData = nil
    }

    init(inlineData: InlineData) {
        self.text = nil
        self.inlineData = inlineData
    }
}

private struct InlineData: Codable {
    let mimeType: String
    let data: String
}

private struct GenerationConfig: Encodable {
    let temperature: Double
    let responseMimeType: String
}

private struct TTSInteractionRequest: Encodable {
    let model: String
    let input: String
    let responseFormat: TTSResponseFormat
    let generationConfig: TTSGenerationConfig

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case responseFormat = "response_format"
        case generationConfig = "generation_config"
    }
}

private struct TTSResponseFormat: Encodable {
    let type: String
}

private struct TTSGenerationConfig: Encodable {
    let speechConfig: [TTSSpeechConfig]

    enum CodingKeys: String, CodingKey {
        case speechConfig = "speech_config"
    }
}

private struct TTSSpeechConfig: Encodable {
    let voice: String
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]?

    struct Candidate: Decodable {
        let content: Content?

        struct Content: Decodable {
            let parts: [Part]?

            struct Part: Decodable {
                let text: String?
            }
        }
    }
}

private struct TTSInteractionResponse: Decodable {
    let status: String?
    let steps: [Step]?

    struct Step: Decodable {
        let type: String?
        let content: [Content]?
    }

    struct Content: Decodable {
        let type: String
        let data: String?
        let mimeType: String?
        let sampleRate: Int?
        let channels: Int?
    }
}

private struct GeminiErrorResponse: Decodable {
    let error: ErrorBody

    struct ErrorBody: Decodable {
        let message: String
    }
}

private struct AssistantPayload: Decodable {
    let transcript: String?
    let answer: String
    let shouldSaveUserMemory: Bool?
    let userMemory: UserMemoryDraft?
    let action: AssistantAction?
    let timeDetail: TimeDetail?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

//
//  GeminiService.swift
//  MetaGemini
//

import Foundation

enum GeminiServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Gemini API 키가 없습니다. Secrets.xcconfig에 GEMINI_API_KEY를 설정해주세요."
        case .invalidResponse:
            return "Gemini에서 이해할 수 없는 응답을 받았습니다."
        case .serviceError(let message):
            return "Gemini 요청에 실패했습니다: \(message)"
        }
    }
}

struct AssistantResult {
    let transcript: String?
    let answer: String
    let memo: MemoDraft?
}

struct GeminiService {
    private let model = "gemini-3.6-flash"

    func answerVoiceQuestion(audioURL: URL) async throws -> AssistantResult {
        let audioData = try Data(contentsOf: audioURL)
        return try await generate(
            instruction: """
            사용자의 음성 질문을 한국어로 전사하고 답하세요. 일정, 메모, 아이디어 정리 요청에는 간결하고 실용적으로 답하세요.
            사용자가 '기억해', '메모해', '저장해' 같은 의도를 표현한 경우에만 memo를 채우세요.
            """,
            audioData: audioData,
            imageData: nil
        )
    }

    func describeScene(imageData: Data) async throws -> AssistantResult {
        try await generate(
            instruction: """
            사용자가 보는 장면을 한국어로 2~3문장 안에서 설명하세요. 보이는 물체, 읽을 수 있는 핵심 텍스트,
            사용자가 다음에 취할 수 있는 실용적인 행동을 우선해서 말하세요. 확실하지 않은 정보는 추측이라고 밝혀야 합니다.
            """,
            audioData: nil,
            imageData: imageData
        )
    }

    private func generate(
        instruction: String,
        audioData: Data?,
        imageData: Data?
    ) async throws -> AssistantResult {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "GeminiAPIKey") as? String,
              !apiKey.isEmpty,
              !apiKey.contains("$")
        else {
            throw GeminiServiceError.missingAPIKey
        }

        let systemPrompt = """
        당신은 Lumi, Ray-Ban Meta와 함께 동작하는 개인 AI 비서입니다.
        \(instruction)

        반드시 아래 JSON만 반환하세요. Markdown 코드 블록을 쓰지 마세요.
        {
          "transcript": "음성 입력의 한국어 전사. 이미지 전용이면 빈 문자열",
          "answer": "사용자에게 들려줄 한국어 답변",
          "memo": { "title": "짧은 제목", "body": "저장할 내용" } 또는 null
        }
        """

        var parts = [GeminiPart(text: "음성 또는 이미지 입력을 분석해 주세요.")]
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
            return AssistantResult(
                transcript: payload.transcript?.nilIfEmpty,
                answer: payload.answer,
                memo: payload.memo
            )
        }

        return AssistantResult(transcript: nil, answer: cleanedText, memo: nil)
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

private struct GeminiErrorResponse: Decodable {
    let error: ErrorBody

    struct ErrorBody: Decodable {
        let message: String
    }
}

private struct AssistantPayload: Decodable {
    let transcript: String?
    let answer: String
    let memo: MemoDraft?
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

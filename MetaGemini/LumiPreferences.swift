//
//  LumiPreferences.swift
//  MetaGemini
//

import Foundation

enum LumiResponseTone: String, CaseIterable, Identifiable {
    case concise
    case detailed
    case jarvis
    case work

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concise: return "간결함"
        case .detailed: return "자세한 설명"
        case .jarvis: return "친근한 자비스"
        case .work: return "업무 중심"
        }
    }

    var description: String {
        switch self {
        case .concise: return "핵심만 짧게 알려드려요."
        case .detailed: return "맥락과 다음 행동까지 충분히 설명해요."
        case .jarvis: return "차분하고 친근한 개인 비서처럼 말해요."
        case .work: return "결론, 일정, 할 일을 우선해 정리해요."
        }
    }

    var responseInstruction: String {
        switch self {
        case .concise:
            return "답변 톤은 간결함입니다. 결론부터 한두 문장으로 말하고 꼭 필요한 경우에만 짧은 보충을 덧붙이세요."
        case .detailed:
            return "답변 톤은 자세한 설명입니다. 핵심 결론 뒤에 근거, 맥락, 실용적인 다음 행동을 자연스럽게 덧붙이세요. 장황하게 반복하지 마세요."
        case .jarvis:
            return "답변 톤은 친근한 자비스입니다. 차분하고 자신감 있는 개인 비서처럼 따뜻하게 말하되, 과장된 역할극이나 호칭 반복은 하지 마세요."
        case .work:
            return "답변 톤은 업무 중심입니다. 결론과 실행 항목을 우선하고, 날짜·시간·결정 사항은 분명하게 정리하세요."
        }
    }

    var speechDirection: String {
        switch self {
        case .concise:
            return "Keep the delivery crisp, direct, and brief with minimal pauses."
        case .detailed:
            return "Use an explanatory, unhurried pace with clear pauses between key points."
        case .jarvis:
            return "Sound warm, composed, confident, and lightly conversational, like a trusted personal assistant."
        case .work:
            return "Sound focused, clear, and professional, emphasizing dates, decisions, and next steps."
        }
    }
}

enum LumiPreferences {
    static let confirmBeforeActionKey = "lumi.confirm-before-action"
    static let experimentalKeyboardInputKey = "lumi.experimental-keyboard-input"
    static let responseToneKey = "lumi.response-tone"

    static var confirmsActionsBeforeExecution: Bool {
        guard UserDefaults.standard.object(forKey: confirmBeforeActionKey) != nil else {
            return true
        }

        return UserDefaults.standard.bool(forKey: confirmBeforeActionKey)
    }

    static var responseTone: LumiResponseTone {
        let rawValue = UserDefaults.standard.string(forKey: responseToneKey)
        return LumiResponseTone(rawValue: rawValue ?? "") ?? .jarvis
    }
}

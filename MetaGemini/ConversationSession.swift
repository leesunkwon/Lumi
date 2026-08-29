//
//  ConversationSession.swift
//  MetaGemini
//

import Foundation

enum ConversationMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

struct ConversationMessage: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let role: ConversationMessageRole
    let text: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: ConversationMessageRole,
        text: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}

struct ConversationSession: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var messages: [ConversationMessage]

    init(
        id: UUID = UUID(),
        title: String = "새 대화",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        messages: [ConversationMessage] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    var preview: String {
        messages.last?.text ?? "안경으로 새로운 질문을 시작해보세요."
    }
}

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
    let photoFilename: String?
    let memoryReferenceIDs: [UUID]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: ConversationMessageRole,
        text: String,
        photoFilename: String? = nil,
        memoryReferenceIDs: [UUID] = [],
        createdAt: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.photoFilename = photoFilename
        self.memoryReferenceIDs = memoryReferenceIDs
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case role
        case text
        case photoFilename
        case memoryReferenceIDs
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(ConversationMessageRole.self, forKey: .role)
        text = try container.decode(String.self, forKey: .text)
        photoFilename = try container.decodeIfPresent(String.self, forKey: .photoFilename)
        memoryReferenceIDs = try container.decodeIfPresent([UUID].self, forKey: .memoryReferenceIDs) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
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

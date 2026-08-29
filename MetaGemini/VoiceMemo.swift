//
//  VoiceMemo.swift
//  MetaGemini
//

import Foundation

struct VoiceMemo: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let body: String
    let createdAt: Date

    init(id: UUID = UUID(), title: String, body: String, createdAt: Date = .now) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }
}

struct MemoDraft: Codable {
    let title: String
    let body: String
}

//
//  VoiceMemo.swift
//  MetaGemini
//

import Foundation

enum UserMemoryCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case general
    case schedule
    case parking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "일반"
        case .schedule:
            return "일정"
        case .parking:
            return "주차 기억"
        }
    }

    var symbol: String {
        switch self {
        case .general:
            return "bookmark"
        case .schedule:
            return "calendar"
        case .parking:
            return "parkingsign.circle"
        }
    }

    static func resolved(from rawValue: String?) -> UserMemoryCategory {
        guard let rawValue else { return .general }
        if rawValue == "task" { return .schedule }
        return UserMemoryCategory(rawValue: rawValue) ?? .general
    }
}

enum UserMemoryDateFilter: Hashable {
    case all
    case today
    case yesterday
    case thisWeek
    case custom

    var title: String {
        switch self {
        case .all:
            return "전체 날짜"
        case .today:
            return "오늘"
        case .yesterday:
            return "어제"
        case .thisWeek:
            return "이번 주"
        case .custom:
            return "날짜 선택"
        }
    }
}

struct VoiceMemo: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let body: String
    let category: UserMemoryCategory
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        category: UserMemoryCategory = .general,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case category
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        category = UserMemoryCategory.resolved(
            from: try container.decodeIfPresent(String.self, forKey: .category)
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(category, forKey: .category)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct UserMemoryDraft: Codable {
    let title: String
    let body: String
    let category: UserMemoryCategory

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case category
    }

    init(title: String, body: String, category: UserMemoryCategory = .general) {
        self.title = title
        self.body = body
        self.category = category
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        category = UserMemoryCategory.resolved(
            from: try container.decodeIfPresent(String.self, forKey: .category)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(category, forKey: .category)
    }
}

//
//  VoiceMemo.swift
//  MetaGemini
//

import Foundation

enum UserMemoryCategory: String, CaseIterable, Codable, Identifiable, Hashable {
    case general
    case schedule
    case parking
    case place

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            return "일반"
        case .schedule:
            return "일정"
        case .parking:
            return "주차 기억"
        case .place:
            return "장소"
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
        case .place:
            return "mappin.and.ellipse"
        }
    }

    static func resolved(from rawValue: String?) -> UserMemoryCategory {
        guard let rawValue else { return .general }
        if rawValue == "task" { return .schedule }
        return UserMemoryCategory(rawValue: rawValue) ?? .general
    }

    static var editableCases: [UserMemoryCategory] {
        [.general, .parking, .place]
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
    let photoFilename: String?
    let location: UserMemoryLocation?
    let tags: [String]
    let visualSummary: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        body: String,
        category: UserMemoryCategory = .general,
        photoFilename: String? = nil,
        location: UserMemoryLocation? = nil,
        tags: [String] = [],
        visualSummary: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.category = category
        self.photoFilename = photoFilename
        self.location = location
        self.tags = Self.normalizedTags(tags)
        self.visualSummary = visualSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case category
        case photoFilename
        case location
        case tags
        case visualSummary
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
        photoFilename = try container.decodeIfPresent(String.self, forKey: .photoFilename)
        location = try container.decodeIfPresent(UserMemoryLocation.self, forKey: .location)
        tags = Self.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(photoFilename, forKey: .photoFilename)
        try container.encodeIfPresent(location, forKey: .location)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(visualSummary, forKey: .visualSummary)
        try container.encode(createdAt, forKey: .createdAt)
    }

    static func normalizedTags(_ tags: [String]) -> [String] {
        var normalized: [String] = []
        var seen: Set<String> = []

        for tag in tags {
            let value = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .replacingOccurrences(of: " ", with: "")
            guard !value.isEmpty else { continue }
            let key = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(key).inserted else { continue }
            normalized.append(String(value.prefix(24)))
            if normalized.count == 8 { break }
        }

        return normalized
    }
}

struct UserMemoryLocation: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let address: String?

    var displayName: String {
        address ?? String(format: "위도 %.5f, 경도 %.5f", latitude, longitude)
    }

    var mapURL: URL? {
        URL(string: "http://maps.apple.com/?ll=\(latitude),\(longitude)")
    }

    var directionsURL: URL? {
        URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=d")
    }
}

struct UserMemoryDraft: Codable {
    let title: String
    let body: String
    let category: UserMemoryCategory
    let tags: [String]
    let visualSummary: String?

    private enum CodingKeys: String, CodingKey {
        case title
        case body
        case category
        case tags
        case visualSummary
    }

    init(
        title: String,
        body: String,
        category: UserMemoryCategory = .general,
        tags: [String] = [],
        visualSummary: String? = nil
    ) {
        self.title = title
        self.body = body
        self.category = category
        self.tags = VoiceMemo.normalizedTags(tags)
        self.visualSummary = visualSummary?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        category = UserMemoryCategory.resolved(
            from: try container.decodeIfPresent(String.self, forKey: .category)
        )
        tags = VoiceMemo.normalizedTags(try container.decodeIfPresent([String].self, forKey: .tags) ?? [])
        visualSummary = try container.decodeIfPresent(String.self, forKey: .visualSummary)?.nilIfEmpty
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(category, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(visualSummary, forKey: .visualSummary)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

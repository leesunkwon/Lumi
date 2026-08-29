//
//  LumiSchedule.swift
//  MetaGemini
//

import Foundation

struct LumiSchedule: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let scheduledAt: Date
    let note: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        scheduledAt: Date,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.scheduledAt = scheduledAt
        self.note = note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.createdAt = createdAt
    }

    var notificationIdentifier: String {
        "lumi.schedule.\(id.uuidString)"
    }

    var isUpcoming: Bool {
        scheduledAt > .now
    }
}

struct LumiTimer: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let startedAt: Date
    let endsAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = .now,
        endsAt: Date
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endsAt = endsAt
    }

    var notificationIdentifier: String {
        "lumi.timer.\(id.uuidString)"
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        max(0, Int(ceil(endsAt.timeIntervalSince(date))))
    }

    func isActive(at date: Date = .now) -> Bool {
        endsAt > date
    }

    func progress(at date: Date = .now) -> Double {
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(startedAt) / total))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

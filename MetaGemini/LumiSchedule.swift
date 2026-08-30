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
    var startedAt: Date
    var endsAt: Date
    var pausedAt: Date?
    var pausedRemainingSeconds: Int?

    init(
        id: UUID = UUID(),
        title: String,
        startedAt: Date = .now,
        endsAt: Date,
        pausedAt: Date? = nil,
        pausedRemainingSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.pausedAt = pausedAt
        self.pausedRemainingSeconds = pausedRemainingSeconds
    }

    var notificationIdentifier: String {
        "lumi.timer.\(id.uuidString)"
    }

    func remainingSeconds(at date: Date = .now) -> Int {
        if let pausedRemainingSeconds {
            return pausedRemainingSeconds
        }
        return max(0, Int(ceil(endsAt.timeIntervalSince(date))))
    }

    func isActive(at date: Date = .now) -> Bool {
        isPaused || endsAt > date
    }

    var isPaused: Bool {
        pausedRemainingSeconds != nil
    }

    func progress(at date: Date = .now) -> Double {
        if isPaused {
            return 0
        }
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

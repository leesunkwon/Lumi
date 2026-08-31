//
//  LumiActionConfirmation.swift
//  MetaGemini
//

import Foundation

enum LumiActionConfirmationKind {
    case userMemory(UserMemoryDraft)
    case updateUserMemory(existing: VoiceMemo, updated: UserMemoryDraft)
    case place
    case parking
    case schedule(ScheduleDraft, Date)
    case timer(TimerDraft)

    var title: String {
        switch self {
        case .userMemory:
            return "사용자 메모리에 저장할까요?"
        case .updateUserMemory:
            return "사용자 메모리를 수정할까요?"
        case .place:
            return "이 장소를 기억할까요?"
        case .parking:
            return "주차 위치를 기억할까요?"
        case .schedule:
            return "일정을 등록할까요?"
        case .timer:
            return "타이머를 시작할까요?"
        }
    }

    var detail: String {
        switch self {
        case .userMemory(let memory):
            return "\(memory.body)"
        case .updateUserMemory(let existing, let updated):
            return "‘\(existing.title)’을 ‘\(updated.title)’으로 바꿔요.\n\(updated.body)"
        case .place:
            return "안경 사진과 현재 위치를 함께 저장해요."
        case .parking:
            return "안경 사진과 현재 위치를 함께 저장해요. 이전 주차 기억은 교체돼요."
        case .schedule(let draft, let scheduledAt):
            return "\(Self.scheduleDateFormatter.string(from: scheduledAt))에 \(draft.title) 일정을 등록해요."
        case .timer(let draft):
            return "\(Self.durationDescription(draft.durationSeconds)) \(draft.title) 타이머를 시작해요."
        }
    }

    var cancellationAnswer: String {
        switch self {
        case .userMemory:
            return "사용자 메모리 저장을 취소했어요."
        case .updateUserMemory:
            return "사용자 메모리 수정을 취소했어요."
        case .place:
            return "장소 기억을 취소했어요."
        case .parking:
            return "주차 위치 저장을 취소했어요."
        case .schedule:
            return "일정 등록을 취소했어요."
        case .timer:
            return "타이머 시작을 취소했어요."
        }
    }

    private static let scheduleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.timeZone = .current
        formatter.dateFormat = "M월 d일 EEEE a h시 mm분"
        return formatter
    }()

    private static func durationDescription(_ durationSeconds: Int) -> String {
        let hours = durationSeconds / 3_600
        let minutes = (durationSeconds % 3_600) / 60
        let seconds = durationSeconds % 60

        if hours > 0 { return "\(hours)시간 \(minutes)분" }
        if minutes > 0 { return "\(minutes)분" }
        return "\(seconds)초"
    }
}

struct PendingLumiAction: Identifiable {
    let id = UUID()
    let kind: LumiActionConfirmationKind
    let result: AssistantResult
    let fallbackUserMessage: String
    let conversationID: UUID?
    let conversation: ConversationSession?
    let userMemories: [VoiceMemo]
    let schedules: [LumiSchedule]
}

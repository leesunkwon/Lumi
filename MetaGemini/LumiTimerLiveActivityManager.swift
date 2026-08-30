//
//  LumiTimerLiveActivityManager.swift
//  MetaGemini
//

import ActivityKit
import Foundation

enum LumiTimerLiveActivityManager {
    static func startOrUpdate(for timer: LumiTimer) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = activityContent(for: timer)
        if let activity = activity(for: timer.id) {
            await activity.update(content)
            return
        }

        let attributes = LumiTimerActivityAttributes(timerID: timer.id, title: timer.title)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    static func end(timerID: UUID) async {
        guard let activity = activity(for: timerID) else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
    }

    private static func activity(for timerID: UUID) -> Activity<LumiTimerActivityAttributes>? {
        Activity<LumiTimerActivityAttributes>.activities.first { activity in
            activity.attributes.timerID == timerID
        }
    }

    private static func activityContent(
        for timer: LumiTimer
    ) -> ActivityContent<LumiTimerActivityAttributes.ContentState> {
        let state = LumiTimerActivityAttributes.ContentState(
            endsAt: timer.endsAt,
            isPaused: timer.isPaused,
            pausedRemainingSeconds: timer.pausedRemainingSeconds
        )
        return ActivityContent(
            state: state,
            staleDate: timer.isPaused ? nil : timer.endsAt
        )
    }
}

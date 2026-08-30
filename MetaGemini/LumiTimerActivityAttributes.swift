//
//  LumiTimerActivityAttributes.swift
//  MetaGemini
//

import ActivityKit
import Foundation

struct LumiTimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let endsAt: Date
        let isPaused: Bool
        let pausedRemainingSeconds: Int?
    }

    let timerID: UUID
    let title: String
}

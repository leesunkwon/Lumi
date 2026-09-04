//
//  LumiNotificationScheduler.swift
//  MetaGemini
//

import Foundation
import UserNotifications

struct LumiNotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func scheduleReminder(for schedule: LumiSchedule) async -> Bool {
        guard await requestAuthorizationIfNeeded() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "Lumi 일정 알림"
        content.body = "지금 \(schedule.title) 일정 시간이에요."
        content.sound = .default
        content.userInfo = ["lumiScheduleID": schedule.id.uuidString]

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: schedule.scheduledAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(
            identifier: schedule.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func scheduleCompletion(for timer: LumiTimer) async -> Bool {
        guard await requestAuthorizationIfNeeded() else { return false }

        let content = UNMutableNotificationContent()
        content.title = "타이머 완료"
        content.body = "\(timer.title) 타이머가 끝났어요."
        content.sound = .default
        content.userInfo = ["lumiTimerID": timer.id.uuidString]

        let interval = max(1, timer.endsAt.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: timer.notificationIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    func cancel(identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound, .badge])
            } catch {
                return false
            }
        case .denied:
            return false
        @unknown default:
            return false
        }
    }
}

//
//  LumiTimerLiveActivity.swift
//  LumiTimerLiveActivity
//

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct LumiTimerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        LumiTimerLiveActivity()
    }
}

struct LumiTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LumiTimerActivityAttributes.self) { context in
            TimerLockScreenView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 10) {
                        Text(context.attributes.title)
                            .font(.headline)
                            .lineLimit(1)

                        TimerCountdownView(state: context.state, style: .expanded)

                        HStack(spacing: 10) {
                            TimerControlLink(
                                action: context.state.isPaused ? "resume" : "pause",
                                timerID: context.attributes.timerID,
                                title: context.state.isPaused ? "재개" : "일시정지",
                                symbol: context.state.isPaused ? "play.fill" : "pause.fill"
                            )
                            TimerControlLink(
                                action: "cancel",
                                timerID: context.attributes.timerID,
                                title: "취소",
                                symbol: "xmark"
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(context.state.isPaused ? .yellow : .white)
            } compactTrailing: {
                TimerCountdownView(state: context.state, style: .compact)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .foregroundStyle(context.state.isPaused ? .yellow : .white)
            }
            .widgetURL(timerURL(action: "open", timerID: context.attributes.timerID))
            .keylineTint(.white)
        }
    }
}

private struct TimerLockScreenView: View {
    let context: ActivityViewContext<LumiTimerActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Lumi 타이머", systemImage: context.state.isPaused ? "pause.fill" : "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(context.attributes.title)
                        .font(.headline)
                        .lineLimit(1)
                }

                Spacer()

                TimerCountdownView(state: context.state, style: .lockScreen)
            }

            HStack(spacing: 10) {
                TimerControlLink(
                    action: context.state.isPaused ? "resume" : "pause",
                    timerID: context.attributes.timerID,
                    title: context.state.isPaused ? "재개" : "일시정지",
                    symbol: context.state.isPaused ? "play.fill" : "pause.fill"
                )
                TimerControlLink(
                    action: "cancel",
                    timerID: context.attributes.timerID,
                    title: "취소",
                    symbol: "xmark"
                )
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(context.attributes.title) 타이머")
    }
}

private struct TimerCountdownView: View {
    enum Style {
        case compact
        case expanded
        case lockScreen
    }

    let state: LumiTimerActivityAttributes.ContentState
    let style: Style

    var body: some View {
        Group {
            if state.isPaused {
                Text(durationText(state.pausedRemainingSeconds ?? 0))
            } else {
                Text(timerInterval: Date.now...state.endsAt, countsDown: true)
            }
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(style == .compact ? .white : .white)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }

    private var font: Font {
        switch style {
        case .compact:
            return .caption2.weight(.bold)
        case .expanded:
            return .system(.title2, design: .rounded, weight: .bold)
        case .lockScreen:
            return .system(.title, design: .rounded, weight: .bold)
        }
    }

    private func durationText(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private struct TimerControlLink: View {
    let action: String
    let timerID: UUID
    let title: String
    let symbol: String

    var body: some View {
        Link(destination: timerURL(action: action, timerID: timerID)) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.white.opacity(0.16), in: Capsule())
        }
        .accessibilityLabel(title)
    }
}

private func timerURL(action: String, timerID: UUID) -> URL {
    var components = URLComponents()
    components.scheme = "lumi"
    components.host = "timer"
    components.queryItems = [
        URLQueryItem(name: "action", value: action),
        URLQueryItem(name: "id", value: timerID.uuidString)
    ]
    return components.url ?? URL(string: "lumi://timer")!
}

import ActivityKit
import AlarmKit
import SwiftUI
import WidgetKit

@main
struct AmmuttaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
        TimerAlarmLiveActivity()
    }
}

/// The active workout on the Lock Screen and in the Dynamic Island.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Palette.navy)
                .activitySystemActionForegroundColor(Palette.iceBlue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.exercise)
                            .font(.headline)
                            .lineLimit(1)
                        Text(context.state.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(attributes: context.attributes, state: context.state)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.iceBlue)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let label = context.state.timerLabel {
                        Text(label)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Palette.iceBlue)
            } compactTrailing: {
                CountdownText(attributes: context.attributes, state: context.state)
                    .monospacedDigit()
                    .foregroundStyle(Palette.iceBlue)
                    .frame(maxWidth: 52)
            } minimal: {
                // The island splits into small bubbles when another activity (such as the
                // rest alarm) is on: keep the countdown visible there too.
                if context.state.hasCountdown, let start = context.state.timerStart, let end = context.state.timerEnd {
                    Text(timerInterval: start...end, countsDown: true)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Palette.iceBlue)
                        .frame(maxWidth: 40)
                } else {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(Palette.iceBlue)
                }
            }
        }
    }
}

/// The system's own Live Activity for a pending rest or set alarm. It can share the Dynamic
/// Island and Lock Screen with the workout's, so it shows the same countdown instead of an
/// empty bubble. When the alarm goes off, the system shows its alert instead.
struct TimerAlarmLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AlarmAttributes<TimerAlarmMetadata>.self) { context in
            AlarmCountdownRow(metadata: context.attributes.metadata)
                .padding(16)
                .activityBackgroundTint(Palette.navy)
                .activitySystemActionForegroundColor(Palette.iceBlue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    AlarmCountdownRow(metadata: context.attributes.metadata)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(Palette.iceBlue)
            } compactTrailing: {
                AlarmCountdown(metadata: context.attributes.metadata)
                    .monospacedDigit()
                    .foregroundStyle(Palette.iceBlue)
                    .frame(maxWidth: 52)
            } minimal: {
                AlarmCountdown(metadata: context.attributes.metadata)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.iceBlue)
                    .frame(maxWidth: 40)
            }
        }
    }
}

private struct AlarmCountdown: View {
    let metadata: TimerAlarmMetadata?

    var body: some View {
        if let metadata, metadata.endsAt > metadata.startsAt {
            Text(timerInterval: metadata.startsAt...metadata.endsAt, countsDown: true)
        } else {
            Image(systemName: "timer")
        }
    }
}

private struct AlarmCountdownRow: View {
    let metadata: TimerAlarmMetadata?

    var body: some View {
        HStack {
            Text(metadata?.label ?? "")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer(minLength: 8)
            AlarmCountdown(metadata: metadata)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(Palette.iceBlue)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110, alignment: .trailing)
        }
    }
}

private struct LockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(attributes.planName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.iceBlue)
                    .lineLimit(1)
                Text(state.exercise)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let label = state.timerLabel {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                CountdownText(attributes: attributes, state: state)
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(state.hasCountdown ? Palette.iceBlue : .white)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140, alignment: .trailing)
            }
        }
        .padding(16)
    }
}

/// The rest or set countdown, or elapsed workout time when no countdown runs.
private struct CountdownText: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.hasCountdown, let start = state.timerStart, let end = state.timerEnd {
            Text(timerInterval: start...end, countsDown: true)
        } else {
            Text(attributes.startedAt, style: .timer)
        }
    }
}

private enum Palette {
    static let navy = Color(red: 12 / 255, green: 19 / 255, blue: 36 / 255)
    static let iceBlue = Color(red: 138 / 255, green: 235 / 255, blue: 1)
}

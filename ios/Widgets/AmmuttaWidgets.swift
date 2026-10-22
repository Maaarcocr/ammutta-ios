import ActivityKit
import SwiftUI
import WidgetKit

@main
struct AmmuttaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorkoutLiveActivity()
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
                Image(systemName: "dumbbell.fill")
                    .foregroundStyle(Palette.iceBlue)
            }
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

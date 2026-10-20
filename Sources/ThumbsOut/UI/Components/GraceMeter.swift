import AppKit
import SwiftUI
import ThumbsOutCore

/// A meter that snaps to the grace-period stops. While a grace period is counting down,
/// the time left is drawn as an amber bar inside the track.
struct GraceMeter: View {
    @Binding var minutes: Int
    /// Minutes left in a running grace period, if any.
    var remainingMinutes: Double?
    var tint: Color = Theme.working

    private let stops = GracePeriodScale.minutes
    private let trackHeight: CGFloat = 6
    private let knobSize: CGFloat = 18

    private var selectedIndex: Int { GracePeriodScale.nearestIndex(for: minutes) }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geometry in
                let step = stepWidth(for: geometry.size.width)
                ZStack(alignment: .leading) {
                    track(step: step)
                    knob.offset(x: CGFloat(selectedIndex) * step)
                }
                .frame(height: knobSize)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        select(index: Int(((value.location.x - knobSize / 2) / step).rounded()))
                    }
                )
            }
            .frame(height: knobSize)

            GeometryReader { geometry in
                let step = stepWidth(for: geometry.size.width)
                ForEach(stops.indices, id: \.self) { index in
                    Text(GracePeriodScale.tickLabel(for: stops[index]))
                        .font(.system(size: 9, weight: index == selectedIndex ? .bold : .regular).monospacedDigit())
                        .foregroundStyle(index == selectedIndex ? AnyShapeStyle(Theme.workingInk) : AnyShapeStyle(.tertiary))
                        .fixedSize()
                        .position(x: knobSize / 2 + CGFloat(index) * step, y: 6)
                }
            }
            .frame(height: 12)
        }
        .animation(.snappy(duration: 0.18), value: selectedIndex)
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { Double(selectedIndex) }, set: { select(index: Int($0.rounded())) }),
                in: 0...Double(stops.count - 1),
                step: 1
            ) { Text("Stay awake after the last command") }
                .accessibilityValue(spokenValue)
        }
    }

    /// Never zero, so a very narrow layout can't divide by zero while dragging.
    private func stepWidth(for width: CGFloat) -> CGFloat {
        max((width - knobSize) / CGFloat(stops.count - 1), 1)
    }

    private var spokenValue: String {
        let setting = minutes == 0
            ? "No grace period"
            : Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        guard let remainingMinutes else { return setting }
        let left = Duration.seconds(Int(remainingMinutes * 60))
            .formatted(.units(allowed: [.hours, .minutes], width: .wide))
        return "\(setting), \(left) left"
    }

    private func track(step: CGFloat) -> some View {
        let inset = knobSize / 2
        let selectedWidth = CGFloat(selectedIndex) * step
        return ZStack(alignment: .leading) {
            Capsule().fill(Color.primary.opacity(0.1))
            Capsule().fill(tint.opacity(0.85))
                .frame(width: selectedWidth + trackHeight)
            if let remainingMinutes {
                Capsule().fill(Theme.grace)
                    .frame(width: CGFloat(GracePeriodScale.position(for: remainingMinutes)) * step + trackHeight)
            }
            ForEach(stops.indices, id: \.self) { index in
                Circle()
                    .fill(index <= selectedIndex ? Color.white.opacity(0.8) : Color.primary.opacity(0.25))
                    .frame(width: 3, height: 3)
                    .offset(x: CGFloat(index) * step + (trackHeight - 3) / 2)
            }
        }
        .frame(height: trackHeight)
        .padding(.horizontal, inset - trackHeight / 2)
    }

    private var knob: some View {
        Circle()
            .fill(.white)
            .frame(width: knobSize, height: knobSize)
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5))
    }

    private func select(index: Int) {
        let clamped = min(max(index, 0), stops.count - 1)
        guard clamped != selectedIndex else { return }
        minutes = stops[clamped]
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

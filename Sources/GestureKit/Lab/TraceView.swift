#if os(visionOS)
import GestureCore
import SwiftUI

/// A `TraceRecorder`'s interactions, newest first, each a timeline of its
/// events: what it was on, its outcome and how long it lasted, a track with
/// a mark at each event's time, and each event's time, name, and detail.
/// Large, white on black, so a screen recording made on the headset reads
/// it, and it updates as the recorder shows its log (`shownLog`), at most
/// ten times a second.
///
/// It takes all the room it's offered, whatever it shows, and lays out what
/// it shows in that room alone, so an event, which changes what it shows,
/// lays out nothing beside it again. Laid out as an ordinary view, it had
/// each event lay out again whatever stood beside it in a stack: in
/// GestureLab's window, every slider of the station's tuning, which made an
/// event cost three times what the trace itself did.
public struct TraceView: View {
    private let recorder: TraceRecorder
    private let title: String

    /// The trace of `recorder`, headed `title`.
    public init(_ recorder: TraceRecorder, title: String = "Trace") {
        self.recorder = recorder
        self.title = title
    }

    public var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                TraceViewContent(recorder: recorder, title: title)
            }
    }
}

/// What a `TraceView` shows, laid out in the room the view takes.
private struct TraceViewContent: View {
    let recorder: TraceRecorder
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 30, weight: .bold))
                Spacer()
                Button("Clear") { recorder.clear() }
                    .disabled(recorder.shownInteractions.isEmpty)
            }
            if recorder.shownInteractions.isEmpty {
                Text("Nothing yet. Try the gesture, and each interaction shows here, newest first.")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(recorder.shownInteractions) { interaction in
                            TraceInteractionTimeline(interaction: interaction)
                                .equatable()
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(.black.opacity(0.88), in: .rect(cornerRadius: 24))
    }
}

/// One interaction in the trace, drawn again only as it changes: an event
/// added, or its outcome given, which is all a `TraceLog` changes of an
/// interaction, so an event redraws its own interaction's timeline and no
/// other.
private struct TraceInteractionTimeline: View, Equatable {
    let interaction: TracedInteraction

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.interaction.id == rhs.interaction.id
            && lhs.interaction.events.count == rhs.interaction.events.count
            && lhs.interaction.outcome == rhs.interaction.outcome
            && lhs.interaction.lasted == rhs.interaction.lasted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("#\(interaction.id)")
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                Text(interaction.title)
                    .font(.system(size: 24, weight: .semibold))
                Spacer(minLength: 12)
                outcome
            }
            Text("\(interaction.gesture) · \(interaction.date.formatted(date: .omitted, time: .standard))")
                .font(.system(size: 17))
                .foregroundStyle(.white.opacity(0.7))
            if !interaction.events.isEmpty {
                TraceEventTrack(interaction: interaction)
                    .frame(height: 22)
                ForEach(interaction.events.indices, id: \.self) { index in
                    let event = interaction.events[index]
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("+\(traceViewSecondsText(event.offset)) s")
                            .font(.system(size: 20).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: 104, alignment: .trailing)
                        Text(event.name)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.cyan)
                        Text(event.detail)
                            .font(.system(size: 20))
                    }
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var outcome: some View {
        if let outcome = interaction.outcome, let lasted = interaction.lasted {
            Text("\(outcome) · \(traceViewSecondsText(lasted)) s")
                .font(.system(size: 22, weight: .bold).monospacedDigit())
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.yellow, in: .capsule)
        } else {
            Text("under way")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.orange, in: .capsule)
        }
    }
}

/// A line across the interaction's time, from its beginning to its outcome
/// or its last event, with a cyan mark at each event's time and a yellow
/// one at its outcome's.
private struct TraceEventTrack: View {
    let interaction: TracedInteraction

    var body: some View {
        GeometryReader { geometry in
            let span = max(
                traceViewSeconds(of: interaction.lasted ?? .zero),
                traceViewSeconds(of: interaction.events.last?.offset ?? .zero),
                0.01
            )
            let width = geometry.size.width - 12
            let x = { (offset: Duration) in 6 + width * traceViewSeconds(of: offset) / span }
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.35))
                    .frame(height: 3)
                    .padding(.horizontal, 6)
                ForEach(interaction.events.indices, id: \.self) { index in
                    Circle()
                        .fill(.cyan)
                        .frame(width: 12, height: 12)
                        .position(x: x(interaction.events[index].offset), y: geometry.size.height / 2)
                }
                if let lasted = interaction.lasted {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.yellow)
                        .frame(width: 4, height: 20)
                        .position(x: x(lasted), y: geometry.size.height / 2)
                }
            }
        }
    }
}

/// A duration in seconds.
private func traceViewSeconds(of duration: Duration) -> Double {
    let (seconds, attoseconds) = duration.components
    return Double(seconds) + Double(attoseconds) / 1e18
}

/// A duration in seconds, to two decimals: "0.50".
private func traceViewSecondsText(_ duration: Duration) -> String {
    String(format: "%.2f", traceViewSeconds(of: duration))
}
#endif

#if os(visionOS)
import GestureCore
import SwiftUI

/// A `TraceRecorder`'s interactions, newest first: the newest two in full,
/// a line for each of their events, a run of one name folded into one line
/// as the log folds it (`TraceLog`); the older ones a line for what they
/// were on and came to, and a line of their stages. White on black, sized
/// so a screen recording made on the headset reads it, and it updates as
/// the recorder shows its log (`shownLog`), at most ten times a second.
///
/// Given a switch (`isOn`), it shows it in its header, to turn tracing on
/// and off; while its recorder isn't recording, it says so and shows
/// nothing else.
///
/// It takes all the room it's offered, whatever it shows, and lays out what
/// it shows in that room alone, so an event, which changes what it shows,
/// lays out nothing beside it again. Laid out as an ordinary view, it had
/// each event lay out again whatever stood beside it in a stack: in
/// GestureLab's window, every slider of the station's tuning, which made an
/// event cost three times what the trace itself did. Its text is what costs
/// as events stream, laid out by Core Text on the main thread at each
/// change, so it shows few lines and changes as few as it can: an event
/// changes its own line, or adds one, and nothing else.
public struct TraceView: View {
    private let recorder: TraceRecorder
    private let title: String
    private let isOn: Binding<Bool>?

    /// The trace of `recorder`, headed `title`, with a switch in its header
    /// bound to `isOn`, if it's given.
    public init(_ recorder: TraceRecorder, title: String = "Trace", isOn: Binding<Bool>? = nil) {
        self.recorder = recorder
        self.title = title
        self.isOn = isOn
    }

    public var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                TraceViewContent(recorder: recorder, title: title, isOn: isOn)
            }
    }
}

/// What a `TraceView` shows, laid out in the room the view takes.
private struct TraceViewContent: View {
    let recorder: TraceRecorder
    let title: String
    let isOn: Binding<Bool>?

    /// How many of the newest interactions show their events.
    private static let expanded = 2

    var body: some View {
        let interactions = recorder.shownInteractions
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Spacer()
                if let isOn {
                    Toggle("Tracing", isOn: isOn)
                        .font(.system(size: 17))
                        .fixedSize()
                }
                Button("Clear") { recorder.clear() }
                    .disabled(interactions.isEmpty)
            }
            if !recorder.isRecording {
                Text("Tracing is off: the gestures write nothing down here, and the console gets at most a line for each.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            } else if interactions.isEmpty {
                Text("Nothing yet. Try the gesture, and each interaction shows here, newest first.")
                    .font(.system(size: 17))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer(minLength: 0)
            } else {
                let expanded = Set(interactions.prefix(Self.expanded).map(\.id))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(interactions) { interaction in
                            TraceInteractionRow(interaction: interaction, isExpanded: expanded.contains(interaction.id))
                                .equatable()
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .background(.black.opacity(0.88), in: .rect(cornerRadius: 24))
    }
}

/// One interaction in the trace, drawn again only as it changes, or as it
/// goes from the newest few to the older ones: an event added or folded, or
/// its outcome given, which is all a `TraceLog` changes of an interaction,
/// so an event redraws its own interaction's row and no other.
private struct TraceInteractionRow: View, Equatable {
    let interaction: TracedInteraction
    let isExpanded: Bool

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isExpanded == rhs.isExpanded && lhs.interaction == rhs.interaction
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("#\(interaction.id)")
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                Text(interaction.title)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                TraceOutcomePill(outcome: interaction.outcome, lasted: interaction.lasted)
            }
            if isExpanded {
                Text("\(interaction.gesture) · \(interaction.date.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
                ForEach(interaction.events.indices, id: \.self) { index in
                    TraceEventLine(event: interaction.events[index])
                        .equatable()
                }
            } else if !interaction.events.isEmpty {
                Text(interaction.events.map(\.nameText).joined(separator: " · "))
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// An interaction's outcome and how long it lasted, or "under way", as a
/// pill.
private struct TraceOutcomePill: View {
    let outcome: String?
    let lasted: Duration?

    var body: some View {
        if let outcome, let lasted {
            Text("\(outcome) · \(traceViewSecondsText(lasted)) s")
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .lineLimit(1)
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.yellow, in: .capsule)
        } else {
            Text("under way")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(.orange, in: .capsule)
        }
    }
}

/// One line of an interaction: its time, its name, a run's count, and what
/// it said, drawn again only as it changes, as a run folds another event
/// in.
private struct TraceEventLine: View, Equatable {
    let event: TraceEvent

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.event == rhs.event
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(event.timeText)
                .font(.system(size: 14).monospacedDigit())
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 104, alignment: .trailing)
            Text(event.nameText)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.cyan)
            Text(event.detailText)
                .font(.system(size: 15))
                .lineLimit(2)
        }
    }
}

/// A duration in seconds, to two decimals: "0.50".
private func traceViewSecondsText(_ duration: Duration) -> String {
    let (seconds, attoseconds) = duration.components
    return String(format: "%.2f", Double(seconds) + Double(attoseconds) / 1e18)
}
#endif

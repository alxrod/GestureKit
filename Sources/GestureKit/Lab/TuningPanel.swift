#if os(visionOS)
import GestureCore
import os
import SwiftUI
import UIKit

private let logger = Logger(subsystem: "net.alexbrodriguez.gesturekit", category: "TuningPanel")

/// A panel that tunes any `Tunable` live, through its `TuningStore`: a
/// slider with its number for each number, a switch for each switch, each
/// value that differs from its default marked with a yellow dot and the
/// default beside it; Defaults, which puts every value back; and Copy
/// tuning, which copies the values as the Swift initializer that makes them
/// (`Tunable.swiftInitializer()`), to paste wherever GestureKit's defaults
/// are to change, and logs it.
public struct TuningPanel<Tuning: Tunable>: View {
    private let store: TuningStore<Tuning>
    private let title: String
    @State private var copied = false

    /// The panel for `store`, headed `title`, or the tuning's Swift name.
    public init(_ store: TuningStore<Tuning>, title: String? = nil) {
        self.store = store
        self.title = title ?? Tuning.swiftName
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 26, weight: .bold))
                Spacer()
                Button("Defaults") { store.resetToDefaults() }
                    .disabled(!store.isTuned)
                Button(copied ? "Copied" : "Copy tuning", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    copy()
                }
            }
            ForEach(Tuning.parameters) { parameter in
                TuningPanelRow(parameter: parameter, value: store.value(of: parameter)) { value in
                    store.set(value, for: parameter)
                }
                .equatable()
            }
        }
        .padding(20)
    }

    private func copy() {
        let swift = store.tuning.swiftInitializer()
        UIPasteboard.general.string = swift
        logger.info("Copied the tuning of \(store.namespace, privacy: .public):\n\(swift, privacy: .public)")
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

/// One value's row in a `TuningPanel`: a slider with its number, or a
/// switch, its yellow dot and its default beside it while it differs from
/// the default. It's drawn again only as its own value changes, so a slider
/// dragged draws its own row again and none of the panel's others, which a
/// panel drawing every row itself did at each step of any one.
private struct TuningPanelRow<Tuning: Tunable>: View, Equatable {
    let parameter: TuningParameter<Tuning>
    let value: TuningValue
    let set: (TuningValue) -> Void

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.parameter.key == rhs.parameter.key && lhs.value == rhs.value
    }

    var body: some View {
        if parameter.isSwitch {
            switchRow
        } else {
            sliderRow
        }
    }

    private var sliderRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                tunedMark
                Text(parameter.title)
                    .font(.system(size: 20, weight: .medium))
                Spacer()
                Text(parameter.text(for: value))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
            }
            // Unstepped, its value fitted to the step as it's set
            // (`TuningStore.set`), so it still moves a step at a time: a
            // stepped slider draws a mark at each step, up to 361 of them on
            // one, which made each value set cost more than all else in a
            // station's window, in proportion to every stepped slider there.
            Slider(
                value: Binding(
                    get: { value.number ?? parameter.range.lowerBound },
                    set: { set(.number($0)) }
                ),
                in: parameter.range
            ) {
                Text(parameter.title)
            } minimumValueLabel: {
                Text(parameter.text(for: .number(parameter.range.lowerBound)))
                    .font(.system(size: 15).monospacedDigit())
            } maximumValueLabel: {
                Text(parameter.text(for: .number(parameter.range.upperBound)))
                    .font(.system(size: 15).monospacedDigit())
            }
            if value != parameter.defaultValue {
                Text("Default \(parameter.text(for: parameter.defaultValue))")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityValue(parameter.text(for: value))
    }

    private var switchRow: some View {
        HStack(spacing: 10) {
            tunedMark
            Toggle(isOn: Binding(
                get: { value.isOn ?? false },
                set: { set(.toggle($0)) }
            )) {
                Text(parameter.title)
                    .font(.system(size: 20, weight: .medium))
            }
        }
    }

    /// A yellow dot beside a value that differs from its default; clear
    /// room otherwise, so the titles line up.
    private var tunedMark: some View {
        Circle()
            .fill(value != parameter.defaultValue ? Color.yellow : .clear)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}
#endif

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
                if parameter.isSwitch {
                    switchRow(parameter)
                } else {
                    sliderRow(parameter)
                }
            }
        }
        .padding(20)
    }

    private func sliderRow(_ parameter: TuningParameter<Tuning>) -> some View {
        let value = store.value(of: parameter)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                tunedMark(parameter, value)
                Text(parameter.title)
                    .font(.system(size: 20, weight: .medium))
                Spacer()
                Text(parameter.text(for: value))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
            }
            Slider(
                value: Binding(
                    get: { store.value(of: parameter).number ?? parameter.range.lowerBound },
                    set: { store.set(.number($0), for: parameter) }
                ),
                in: parameter.range,
                step: parameter.step
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

    private func switchRow(_ parameter: TuningParameter<Tuning>) -> some View {
        let value = store.value(of: parameter)
        return HStack(spacing: 10) {
            tunedMark(parameter, value)
            Toggle(isOn: Binding(
                get: { store.value(of: parameter).isOn ?? false },
                set: { store.set(.toggle($0), for: parameter) }
            )) {
                Text(parameter.title)
                    .font(.system(size: 20, weight: .medium))
            }
        }
    }

    /// A yellow dot beside a value that differs from its default; clear
    /// room otherwise, so the titles line up.
    private func tunedMark(_ parameter: TuningParameter<Tuning>, _ value: TuningValue) -> some View {
        Circle()
            .fill(value != parameter.defaultValue ? Color.yellow : .clear)
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
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
#endif

#if os(visionOS) && DEBUG
import GestureCore
import SwiftUI
import UIKit

extension View {
    /// In a debug build, reads what the platform's scroll view around this
    /// view has, for `model`'s status line and its alarms: whether it
    /// scrolls, whether its pan is on, the pan's state, and whether it's
    /// tracking, dragging, or coasting; and tells the model each time its
    /// pan changes state, as it begins. Place it inside the scroll view's
    /// content, as on its grid:
    ///
    ///     ScrollView {
    ///         LazyVGrid(columns: columns) { … }
    ///             .pluckScrollViewProbe(container)
    ///     }
    ///     .pluckContainer(container, tuning: tuning, trace: recorder)
    ///
    /// SwiftUI's scroll view on visionOS is a UIKit scroll view, found up the
    /// probe's views. What the probe reads is what the scroll view itself
    /// has, which the value `.scrollDisabled` was given may not be.
    public func pluckScrollViewProbe(_ model: PluckContainerModel) -> some View {
        background(PluckScrollViewProbeRepresentable(model: model))
    }
}

/// The probe, a clear view behind the scroll view's content that takes no
/// touches.
private struct PluckScrollViewProbeRepresentable: UIViewRepresentable {
    let model: PluckContainerModel

    func makeUIView(context: Context) -> PluckScrollViewProbeView {
        let view = PluckScrollViewProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.model = model
        return view
    }

    func updateUIView(_ view: PluckScrollViewProbeView, context: Context) {
        view.model = model
    }
}

/// Finds the scroll view up its views as it joins a window, watches its pan,
/// and reads it for the model.
final class PluckScrollViewProbeView: UIView {
    weak var model: PluckContainerModel? {
        didSet { attach() }
    }

    private weak var scrollView: UIScrollView?
    private var lastPanState: UIGestureRecognizer.State?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }

    private func attach() {
        guard window != nil, let model else { return }
        var view = superview
        while let current = view, !(current is UIScrollView) {
            view = current.superview
        }
        guard let found = view as? UIScrollView else { return }
        if found !== scrollView {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(panChanged(_:)))
            scrollView = found
            found.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        }
        model.scrollViewReader = { [weak self] in self?.reading() }
    }

    /// The pan changed state: the model hears of each new state, its every
    /// change while it moves aside.
    @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
        guard pan.state != lastPanState else { return }
        lastPanState = pan.state
        model?.scrollViewPanChanged(panBegan: pan.state == .began)
    }

    /// What the scroll view has now.
    func reading() -> PluckHoldWatch<AnyHashable>.ScrollViewReading? {
        guard let scrollView else { return nil }
        let pan = scrollView.panGestureRecognizer
        return .init(
            scrollEnabled: scrollView.isScrollEnabled,
            panEnabled: pan.isEnabled,
            panState: pluckProbePanStateName(pan.state),
            tracking: scrollView.isTracking,
            dragging: scrollView.isDragging,
            decelerating: scrollView.isDecelerating
        )
    }
}

/// A gesture recognizer's state in a word.
private func pluckProbePanStateName(_ state: UIGestureRecognizer.State) -> String {
    switch state {
    case .possible: "possible"
    case .began: "began"
    case .changed: "changed"
    case .ended: "ended"
    case .cancelled: "cancelled"
    case .failed: "failed"
    @unknown default: "unknown"
    }
}
#endif

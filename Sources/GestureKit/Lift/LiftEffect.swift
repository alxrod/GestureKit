#if os(visionOS)
import CoreGraphics
import SwiftUI

/// How a view shows lifted off what it lies on, as an item a pinch has
/// lifted out of its grid does: scaled up a little about its middle and
/// brought toward the viewer, on a spring that overshoots a little as it
/// pops out, over a soft shadow left lying where it was, and above its
/// neighbors while it's up and coming down; and, as the pinch holding it
/// tugs it, drawn a little way along with the hand (`liftFollowEffect(_:)`).
///
/// Only the drawing moves (`liftEffect(_:style:)`), so a gesture on a view
/// around it, and a geometry reader around it, measure the same points
/// whether it's lifted or not.
public struct LiftStyle: Sendable, Equatable {
    /// How much larger it shows lifted: 1.08, 8%, so an item of 300 pt
    /// grows about 24 pt, 12 pt past each edge.
    public var scale: CGFloat
    /// How far toward the viewer it stands lifted, in its points: 36 pt,
    /// about 2.6 cm at a window's own size.
    public var depth: CGFloat
    /// Whether it casts its shadow on what it lies on while it's lifted.
    public var castsShadow: Bool

    public init(scale: CGFloat = 1.08, depth: CGFloat = 36, castsShadow: Bool = true) {
        self.scale = scale
        self.depth = depth
        self.castsShadow = castsShadow
    }

    /// The lift as it's tuned by default.
    public static var standard: LiftStyle { LiftStyle() }

    /// The spring a lift pops out on, and its scale comes back on: a third
    /// of a second, with enough bounce that it overshoots by about a tenth.
    public static var springUp: Animation { .spring(duration: 0.32, bounce: 0.4) }

    /// The same spring without its bounce, which brings the depth back down:
    /// the bouncy one would overshoot behind what it lies on, where a
    /// window's glass draws over it.
    public static var springDown: Animation { .spring(duration: 0.32, bounce: 0) }

    /// How long a view coming down stays above its neighbors, for the spring
    /// to bring it all the way down first.
    public static var settleTime: Duration { .seconds(0.6) }

    /// The spring a lifted view follows a pinch's tug on: a tenth of a second
    /// and a little more, with no bounce, so it smooths the drag's steps, as
    /// the 4 pt ones its depth comes in, without lagging the hand.
    public static var followSpring: Animation { .spring(duration: 0.12, bounce: 0) }

    /// The shadow: black at this opacity, blurred, dropped below the view,
    /// as big as it shows lifted, so it shows mostly below it, a little at
    /// its sides, and not above it.
    static let shadowOpacity = 0.5
    static let shadowBlur: CGFloat = 12
    static let shadowDrop: CGFloat = 16
    /// How far in front of what it lies on the shadow lies, in points: just
    /// in front of the neighbors, so it falls on them, and well behind the
    /// lifted view.
    static let shadowLift: CGFloat = 2
    /// The room around the view the shadow is drawn in: as far as it reaches
    /// past the view, its lift's growth, its drop, and its blur.
    static let shadowRoom: CGFloat = 56
}

extension View {
    /// Lifts this drawing while `isLifted`: scaled up and brought toward the
    /// viewer on the spring up, its depth coming down on the spring without
    /// the bounce; with its shadow, if the style casts one, lying where it
    /// was.
    public func liftEffect(_ isLifted: Bool, style: LiftStyle = .standard) -> some View {
        scaleEffect(isLifted ? style.scale : 1)
            .animation(LiftStyle.springUp, value: isLifted)
            .offset(z: isLifted ? style.depth : 0)
            .animation(isLifted ? LiftStyle.springUp : LiftStyle.springDown, value: isLifted)
            .modifier(LiftShadowModifier(isLifted: isLifted && style.castsShadow, scale: style.scale))
    }

    /// Draws this lifted view `offset` from where it stands lifted, in its
    /// points, x across, y down, z toward the viewer, as a pinch holding it
    /// tugs it: following on `LiftStyle.followSpring`, and back to its place
    /// on the spring without the bounce as the offset goes to zero, as when
    /// it breaks free of the pinch's tether or settles. Only the drawing
    /// moves. Apply it inside `liftEffect(_:style:)`, so the lift's shadow
    /// stays lying where the view was.
    public func liftFollowEffect(_ offset: SIMD3<Double>) -> some View {
        self.offset(x: CGFloat(offset.x), y: CGFloat(offset.y))
            .offset(z: CGFloat(offset.z))
            .animation(offset == .zero ? LiftStyle.springDown : LiftStyle.followSpring, value: offset)
    }

    /// Raises this view above its neighbors, in a grid or a stack, while
    /// `isLifted`, and for `LiftStyle.settleTime` after, while its spring
    /// brings it down, so it stays in front of them where it overlaps them.
    public func raisedWhileLifted(_ isLifted: Bool) -> some View {
        modifier(LiftRaiseModifier(isLifted: isLifted))
    }
}

/// Lays the lift's shadow on what the view lies on, fading in with the lift
/// and out as it comes down; only a lifted view, or one coming down, has
/// one, so the views around it carry nothing more as they scroll.
private struct LiftShadowModifier: ViewModifier {
    let isLifted: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.spatialOverlay(alignment: .back) {
            ZStack {
                if isLifted {
                    LiftShadowView(scale: scale)
                        .transition(.opacity)
                }
            }
            .animation(LiftStyle.springUp, value: isLifted)
        }
    }
}

/// The soft shadow a lifted view casts: it doesn't lift, lying just in front
/// of the neighbors it falls on, as big as the view shows lifted and dropped
/// below it. It takes no looks or pinches, and VoiceOver passes over it.
///
/// It's one image, drawn once and stretched, rather than a blur: a view
/// standing off a window drew no blur in the simulator, nor anything past
/// its own frame, and a canvas drawing its blur as the view lifted held up
/// the lift's spring.
private struct LiftShadowView: View {
    let scale: CGFloat

    var body: some View {
        if let art = LiftShadowArt.image {
            Image(decorative: art, scale: 1)
                .resizable()
                .interpolation(.high)
                .scaleEffect(scale)
                .offset(z: LiftStyle.shadowLift)
                .padding(-LiftStyle.shadowRoom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// The lift's shadow as one image, made once: over a view of
/// `referenceSide` and `LiftStyle.shadowRoom` around it, the view's square,
/// dropped `shadowDrop`, blurred `shadowBlur`, in black at `shadowOpacity`.
/// A view of another size stretches it, its shadow a little larger or
/// smaller about it. Nil, and no shadow, should it fail to be made.
@MainActor
private enum LiftShadowArt {
    /// The view it's drawn for, in points, and the image's side, in pixels.
    private static let referenceSide: CGFloat = 300
    private static let pixels = 256

    static let image: CGImage? = {
        let room = LiftStyle.shadowRoom
        let side = referenceSide + 2 * room
        let perPoint = CGFloat(pixels) / side
        let square = referenceSide * perPoint
        let inset = (CGFloat(pixels) - square) / 2
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        // Only the shadow lands in the image: the square is drawn a whole
        // image to the left, and its shadow cast that far right, dropped,
        // as y runs up here.
        let drawn = CGRect(x: inset - CGFloat(pixels), y: inset - LiftStyle.shadowDrop * perPoint, width: square, height: square)
        context.setShadow(
            offset: CGSize(width: CGFloat(pixels), height: 0),
            blur: 2 * LiftStyle.shadowBlur * perPoint,
            color: CGColor(gray: 0, alpha: LiftStyle.shadowOpacity)
        )
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(drawn)
        return context.makeImage()
    }()
}

/// Raises a view above its neighbors while it's lifted, and for
/// `LiftStyle.settleTime` after, while its spring brings it down.
private struct LiftRaiseModifier: ViewModifier {
    let isLifted: Bool

    /// Whether it stays raised as it comes down.
    @State private var isComingDown = false

    func body(content: Content) -> some View {
        content
            .zIndex(isLifted || isComingDown ? 1 : 0)
            .onChange(of: isLifted) { _, lifted in
                isComingDown = !lifted
            }
            .task(id: isComingDown) {
                guard isComingDown else { return }
                try? await Task.sleep(for: LiftStyle.settleTime)
                guard !Task.isCancelled else { return }
                isComingDown = false
            }
    }
}
#endif

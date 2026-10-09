# GestureKit

Content-agnostic gestures for Apple Vision Pro, settled on the headset
rather than in the simulator, which can't pinch.

- **Carry**: a grab handle carries a thing 1:1 with the hand, never nearer
  your head than 0.3 m: a clear handle entity with a hover glow, and an
  entity-targeted drag that tells you each step, or moves the entity for
  you.
- **Facing**: a thing turns to face you, standing on a point or hanging
  from one, once or every frame as you move, with world tracking for where
  your head is.
- **Placement**: a panel opens below your gaze, tilted up to you, and stays
  put until you carry it by the pill under it.
- **Pluck**: pull an item out of a scrolling grid into the room. A pinch
  that moves first scrolls; held still, the item lifts; a moment later, a
  pull toward you takes it out.
- **Press**: one pinch on a surface, told as a tap, a drag along or across,
  a pickup and carry, or a hold. Held still, what you pinched lifts toward
  you, and a move then carries it.
- **Coast**: a scroll let go on the move coasts on, slowing, and a pinch
  catches it.
- **Hold watch**: a still hold on a handle or control, beside its own drag
  and tap, never in front of them.

Work in progress: some of these are still on their way in, in the order
`docs/design.md` gives.

## Two libraries

- `GestureCore`: each gesture's rules and math, plain Swift for macOS 14+
  and visionOS 26, tested on the Mac. Each takes a tuning, a struct of the
  numbers it goes by, with defaults.
- `GestureKit`: the visionOS side, components, systems, and view
  modifiers that work on any RealityKit entity or SwiftUI view, reporting
  what happens through closures, so your app keeps its own state. It
  re-exports `GestureCore`.

## Adding the package

In `Package.swift`:

```swift
.package(url: "https://github.com/alxrod/GestureKit.git", branch: "main"),
```

and `.product(name: "GestureKit", package: "GestureKit")` in your visionOS
target's dependencies, or `GestureCore` alone for the rules. In Xcode, add
the package by its URL.

## GestureLab

`Lab/` holds GestureLab, a visionOS app with a station for each gesture: a
window listing them, and an immersive space where the chosen one stands.
Beside each, a live trace shows every interaction as a timeline, and a
tuning panel changes its numbers as you try it; Copy tuning puts them on the
pasteboard as Swift, ready to become the defaults.

To run it:

1. Copy `Local.xcconfig.example` to `Local.xcconfig` and set
   `DEVELOPMENT_TEAM` to your team.
2. Open `Lab/GestureLab.xcodeproj`.
3. Run the GestureLab scheme on your Vision Pro, or on the simulator, where
   a click is a pinch.

## Developing

`swift test` runs the core's tests on the Mac; `scripts/build-check.sh`
compile-checks the lab and GestureKit's visionOS side. `AGENTS.md` has the
layout and conventions, and how to add a gesture or a lab station.

## License

MIT; see `LICENSE`.

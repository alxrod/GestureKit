# GestureKit's design

## Why

Vignette, the visionOS app these gestures come from, grew them one round at
a time: carrying a panel by its grab handle, keeping it turned to face you,
placing controls below your gaze, pulling an item out of a scrolling grid,
telling a pinch on a surface as a tap, a drag, a pickup, or a hold. They
kept failing on the headset, and every change was blind, since the
simulator can't pinch.

GestureKit takes that logic out of the app, makes it content-agnostic, and
puts each gesture on a station in a lab app on the headset, with a live trace
of what it did and live tuning of the numbers it goes by. The app then
depends on GestureKit rather than its own copies.

## Two libraries

- **GestureCore**: each gesture's rules and math as plain Swift values,
  with no SwiftUI, RealityKit, or ARKit, building for macOS 14 and visionOS
  26 and tested with `swift test` on the Mac. A rule is told what happened,
  each word with its time on a clock the caller gives
  (`ContinuousClock.Instant`, or seconds), and says what that means: a
  state machine for a pinch, a function for where something stands. Each
  takes a tuning, a struct of every number it goes by, whose defaults are
  the ones settled on the headset.
- **GestureKit**: the visionOS adapters that carry GestureCore's rules out
  on any RealityKit entity or SwiftUI view: components and their
  entity-targeted drags, systems, view modifiers, head tracking, and lift
  visuals. It knows nothing of what it moves: each adapter takes a tuning,
  reports what happens through closures, and leaves the app's state to the
  app. Each takes a `TraceRecorder` too, optionally, so an app that doesn't
  trace passes nothing. Its sources are wrapped in `#if os(visionOS)`, so
  the package builds on the Mac. It re-exports GestureCore.

Nothing in either library names what an app works on: they speak of items,
surfaces, panels, handles, grids, and carried things.

## The gestures

| Area | What it does |
| --- | --- |
| Carry | A grab handle carries a thing 1:1 with the hand, by its middle, never nearer the head than 0.3 m. A pinch waits 8 pt before it carries. A carry ends once, and says how (`CarryEnding`): released, the pinch let go; cancelled, its gesture's state reset with no release a turn of the main actor later; or its view gone mid-carry, as when an immersive space closes. An app that saves where a thing was let go can put it back on the last two, which chose nothing, as Vignette asked on October 10. Core: `CarryPinch`, `CarryEnding`, `HandCarry`, `ViewerCenteredFrame`, `CarryTuning`. Kit: `GrabHandle` and `GrabHandleComponent`, the drag `grabHandleCarry(of:…)` reporting each step through closures, its `onEnd` told the `ending`, and `grabHandlesCarryEntities(…)` with `CarriedEntity`, which move the entity themselves and stand it where the hand last put it however the carry ends. Station: Carry and face. |
| Facing | A thing turns to face the viewer, standing on a point or hanging from one, and keeps its way when the viewer is straight above or below it. Core: `Facing`, `Pose`, `FacingTuning`. Kit: `FacesTheViewerComponent` and its system, frame by frame, and `HeadTracker`, world tracking with the simulator's stand-in (`UntrackedHead`). Station: Carry and face. |
| Placement | A panel opens below the gaze, a set distance out, tilted up to the head, and stays put until carried by its handle. Core: `GazePlacement`, `PanelHandle`, `PlacementTuning`. Kit: `GazePanel`, which stands a panel below the gaze, and `PanelHandleRig` with `PanelHandlePill`, the pill under a panel and its grab handle. Station: Below the gaze. |
| Pluck | An item pulled out of a scrolling grid. A pinch is the grid's scroll unless it's a hold, as Alex asked: one the grid's scroll view scrolls with, or whose scroll offset moves a point from where it stood at the touch, whatever phase the scroll view says it's in, or that moves 10 pt along the scroll, the axes the container gives, vertical by default, or 40 pt any way, before its hold, is the grid's scroll for good; tracking, which the scroll view reports for every pinch from its touch, isn't scrolling. Held still a quarter second with none of those, the item lifts and the scroll stops under it. Lifted, it stays in the grid, held: it follows the hand a little, half the move at first and easing toward 20 pt, as a scroll view's content follows a pinch past its end (`PluckTether`), and the trace says how far the hand has gone of what it needs ("15.0 pt of 34.0 to break free"). A move mostly along the scroll, 10 pt and twice as far along it as across it and in depth, settles the item and gives the pinch back to the scroll (`givesLiftBackToScroll`, on by default), so by default an item can't be pulled out mostly along the scroll axis: up or down out of a grid that scrolls vertically. Whether the scroll view takes up a pinch given back to it, begun while its scroll was off, only the headset can say; if not, the pinch does nothing until it's let go, and nothing spawns. Once the hand has gone 2.5 cm, 34 pt at a window's own size, any other way from where it stood as the item lifted, and two tenths of a second have passed since the lift, the item breaks free and spawns into the room at the hand, settling back into the grid as it does, the scroll staying held until the pinch carrying what spawned lets go; let go before that, it settles, with nothing spawned and no tap. The break-free distance is the hand's: the drag's points are divided by the scale the window is drawn at. The pluck ends at the spawn, handing the pinch to a carry (below). Alex asked for the quarter second and the sticky lift on October 9, the half-second hold having felt long and the 6 mm pull then spawning the item the instant it lifted; that tuning, and the first-shipped 2 cm toward the viewer from the touch, stay a few values away. A pinch that moves less than the drag's 15 pt start in its first quarter second, then scrolls, still lifts, and the lift holds the scroll off until its move along the scroll gives the pinch back. `pluckContainer` marks the scroll view, with its scroll axes, `pluckable` each item, reporting its tap, its lift, `.spawned(at:)`, each `.carried(middle:handMoved:)` step, and `.released(at:)`. A lift stays up past a press that stopping the scroll may cancel, until the pinch is known to be let go: its tap or its drag's end, or, with neither able to come, half a second with nothing heard; and a safety net lets the container's scroll go should its pinch's words never come (below, "When a pluck lets the scroll go"). Nothing on the item but its button competes with the scroll view before the lift: the item's drag is held back by a 60 pt start, which Alex found safe, and brought down at the lift, or held back by its mask, or the lifted pinch is followed by the hand through hand tracking, as the tuning chooses (`PluckLiftedTracking`, below, "The item's drag, competing with the scroll"). |
| HandPinch | A hand's pinch from hand tracking's thumb and index fingertips, closing below 2 cm and opening past 3.5 cm, let go once untracked three tenths of a second, and the hand a press came from, the one whose pinch closed nearest it. Core: `HandPinch`, `HandSide`, `HandPinchTuning`. Kit: `PinchTracker`, ARKit's hand tracking for an open immersive space, which an item follows a lifted pinch by. Station: Pluck. |
| Lift | A view lifted off what it lies on: scaled up and brought toward the viewer on a spring, over its shadow, above its neighbors, coming down without the bounce; and drawn a little way along with a pinch that tugs it, on a quick spring, springing back as it lets go (`liftFollowEffect`). The pluck's items show it, and anything a press picks up can. |
| Press | One pinch on a surface, from its touch, told as a tap, a drag along, a scroll, a drag across, a pickup and carry, or a hold, by how far it moves and how long it's still: held still half a second it picks up, lifting what's drawn; moved 2 cm then, it carries; held a second, it holds. `.surfacePress` on any SwiftUI view or attachment. |
| Coast | A scroll let go on the move coasts on from the hand's speed, slowing by e every 0.8 s and coming to rest at an end rather than stopping dead; a pinch on it while it still goes 5 cm a second catches it, and is no tap. `CoastRun` runs one on a clock, `CoastEasing` animates by it. |
| HoldWatch | A pinch on a handle or control held still 0.6 s asks whether the hold means anything there, watched beside the control's own drag and tap, never in front of them, which then do nothing for the rest of the pinch. `.holdWatch` on any SwiftUI view. |

Each area is a folder of its own in GestureCore and in GestureKit, named as
above, with its tests in `Tests/GestureCoreTests/<Area>/`; Lift, which has no
rules of its own, is in GestureKit alone.

### How a pluck hands over to a carry

A pluck owns its pinch up to the spawn: the hold, the lift, the held
stretch, the break-free, and where what breaks free spawns, the drag's place
pushed 100 pt toward the viewer, in the immersive space's meters. From the
spawn on, the same pinch is a carry's, and the pluck has no movement math of
its own:

    pinch ── held 0.25 s ──▶ lifted, held: the item follows on its tether
          ── 2.5 cm, armed ──▶ .spawned(at:), .settled: the pluck's part ends
          ── each move ──▶ PluckHandoff → CarryPinch → .carried(middle:handMoved:)
                                                     → CarriedEntity.stand
          ── let go ──▶ .released(at:); later pinches: its own grab handle

- The item settles back into its grid as what it pulls out spawns; the
  grid's scroll stays held until the carry's pinch lets go, its drag ending,
  as turning it back on mid-pinch left the grid's scroll view taking no
  pinch after (below).
- `PluckHandoff`, in GestureCore, begins GestureCore's `CarryPinch` at the
  spawn, its middle where it spawned, and hands it each of the hand's
  moves, so the middle goes 1:1 with the hand from where it spawned, by the
  carry's rule. Its tests run a pluck through its break-free into the
  handoff, and the handoff's middle through `HandCarry.pose`.
- The adapter reports each of the carry's steps as
  `.carried(middle:handMoved:)`, which the app stands by the carry's and
  facing's own code, `CarriedEntity.stand`: clear of the head (`HandCarry`),
  facing the viewer (`Facing`). Where the app keeps state of its own, it
  stands the thing there instead, by `HandCarry.pose`.
- Let go, the thing is the app's. Give it a grab handle (`PanelHandleRig`,
  `GrabHandle`) and `grabHandlesCarryEntities` carries it from then on, and
  a `FacesTheViewerComponent` keeps it facing the viewer as they move. The
  Pluck station's cards do all three.

### When a pluck lets the scroll go

A lifted item holds its grid's scroll off, so the hand's moves are the
item's, until its pinch is let go. On October 9 Alex found the scroll
stuck after a pluck: "If you pluck one item, then try scrolling again
sometimes you can get stuck unable to scroll." The hold had outlived the
pinch, and the next pinch, meeting the scroll off as it touched, couldn't
scroll, its scroll view having missed its touch even once something
settled the item at it.

Nothing promises which words a pinch's gestures say as it ends, nor in what
order: the drag's end, its gesture state's reset, the button's press
ending, its tap, the scroll view's phase, the item going. So the tests
replay every ordered choice of them, each said or not, 1,957 orders of six,
around every way a pinch goes, through a grid wired as the adapter wires
GestureCore (`PluckEndReplayTests`, `PluckReplayGrid`), and the next pinch
lands on the same item, another, or empty grid space. They found the
scroll held exactly where the rules waited for a word that couldn't come,
or took a gesture's word for good after its end went unheard:

- **A lift kept up past its press, with no tap.** Stopping the scroll may
  cancel the press as the item lifts, and a cancelled press brings no tap;
  with the drag silent, the hand within its 15 pt start, no word was left.
  The next pinch on an item settled it, too late to scroll; one on empty
  space never did. Most likely the headset's case: lift, let go without
  moving, then scroll.
- **A tap while a gesture still said it had the pinch**, its end unheard,
  which settled only a lift neither gesture had.
- **No word at all** from a gesture that had the pinch: a press on the same
  item joined the stale drag's pinch, and a pinch elsewhere left it alone.

The rules now take each word for what it says (`PluckPinches`):

- A lift kept up past its press is let go once nothing has been heard from
  its pinch for half a second (`PluckTuning.quietRelease`): as long as a hand
  takes to let go and pinch again, and longer than a hand meaning to pull
  takes to move its drag's 15 pt. A hand held still that long, its press
  gone, loses the lift; scrolling comes first.
- The tap is the pinch let go, whatever its gestures still say.
- A press on the item joins its drag's pinch only while the drag has spoken
  within the quiet; a pinch elsewhere settles a lift whose gestures have
  gone quiet.
- Breaking free settles the item; the scroll stays held until the carry's
  pinch lets go (below).

Under them, the container's safety net (`PluckHoldWatch`, run by
`PluckContainerModel`) never holds the scroll without a pinch: it lets the
hold go at once should the held item have no pinch under way, and once
nothing has been heard from its pinch for a second
(`PluckTuning.unheardHoldRelease`), whatever its gestures last said. A
second: a pinch that has its item speaks far more often while it moves, so
a second of silence is a pinch whose words went unheard, or a hand held
perfectly still; it's twice the quiet, so the rules always go first.

To see it on the headset, the watch also raises an alarm once an item has
stayed lifted with no pinch under way for more than half a second, and
every time the net lets go: a red line in the trace with the state and the
last ten things it was told, and one info line in the console. The pluck
station's grid window shows a status line under the grid: the scroll on, or
held by which item, since when, and for how long; the pinch under way, or
the one the rules keep with no gesture having it; and the last alarm, in
red. In the simulator, `-labLoad stuck` says the end words that held the
scroll through the real adapters, by the hand's stand-in (`PinchStandIn`).

#### The scroll view, given on mid-pinch

That round's fix settled the item at the break-free, and the scroll, which
followed the item, came back on there, while the pinch was still down
carrying the card. Alex's clip of October 10 followed: after a pull and its
card carried by its handle, every pinch was told as a scroll by the rules,
the status line said the scroll was on, and the grid's scroll view neither
moved nor said a phase. Replayed, Alex's sequence leaves everything
GestureKit holds right: the container, the watch, and the value given to
`.scrollDisabled` all on, on that fix too, and the card's carry tells the
grid nothing (`PluckScrollHoldReplayTests`). What had changed is when the
scroll came back. SwiftUI's scroll view on visionOS is a UIKit scroll view,
and `.scrollDisabled` turns its pan recognizer off and on, so the
break-free turned the pan back on in the middle of a live touch; a lift
given back to the scroll did the same, which may be the first round's
"sometimes". After that the pan took no pinch.

So the watch now decides what the scroll view is given
(`PluckHoldWatch.holdsTheScroll`, `PluckContainerModel.scrollIsHeldOff`):
held off from the lift until the pinch that took it lets go, an item that
settles while the pinch's drag still has it, at a break-free or a
give-back, leaving the scroll held until that drag ends or is reset, both
of which come as the pinch is let go. A press alone keeps it no longer
than its item. `PluckTuning.scrollComesBackMidPinch`, off, brings the
mid-pinch return back to try again. The safety net covers what's given: a
scroll kept for a pinch whose item settled goes once nothing has been heard
from that pinch for three seconds (`unheardScrollHoldRelease`), longer than
a lift's second, since letting it go while the pinch is still down, as a
carry paused to aim, is what to avoid.

The status line now shows every view side by side: the hold as given and
for which item; the value `.scrollDisabled` got, read where it's given; the
container's hold and lifted item; the watch's; what the UIKit scroll view
itself has, by a debug build's probe (`pluckScrollViewProbe`): its
scrolling, its pan, the pan's state, tracking, dragging, coasting; and its
last phase and when. Alarms are raised when those views disagree for a
quarter second, and when a pinch the rules told as a scroll gets no phase
of scrolling, nor its pan begun, within 0.3 s: "the scroll view never took
it". `-labLoad stuck` ends with the clip, through the real adapters; in the
simulator the probe reads the scroll view "scrolling off, pan off" through
the carry, and "scrolling on, pan on, pan possible" once it's let go.

#### The item's drag, competing with the scroll

That round's alarms caught the rest, in Alex's clip of October 10: single
scrolls eaten, "the scroll view never took it", the scroll view's pan
failing in the instant the item's drag first spoke. The drag, attached from
the touch with a 15 pt start, competed with the scroll view for the pinch,
and won whenever it reached its start before the pan reached its own. On
the headset, a 60 pt start fixed it ("Putting drag start to like 60pt does
actually fix the problem"). But a drag first speaking 60 pt from the touch
does so past the 2.5 cm break-free distance, and the sticky stage is lost.

So the tuning chooses how a lifted pinch is followed
(`PluckTuning.liftedTracking`), switches in order:

- **The drag held back by its start, brought down at the lift**, the
  default: attached from the touch at 60 pt (`heldBackDragStart`), which
  doesn't compete, and brought down to nothing at the lift, the scroll then
  held off. Should the drag's recognizer take its new start mid-pinch, its
  first word comes as soon as the hand moves, and stands for where the pinch
  was as its item lifted, so the sticky stage, the break-free, and the
  hand-off are as before. Should it not, the first word comes at 60 pt from
  the touch, and the pinch is as with the start kept at 60 pt throughout:
  the lifted item follows nothing until then, and breaks free at that word,
  its pull armed, or at the next once it arms.
- **The start kept at 60 pt throughout** (`lowersDragStartAtTheLift` off),
  the known-safe fallback, as Alex tried it, with no sticky stage.
- **The drag held back by its mask** (`holdsDragBackByItsMask`): left out of
  the item's gestures until the lift, then let in. If a gesture let in
  mid-pinch hears it, as with the start brought down; if not, no word comes
  after the lift, the press gone as the lift stops the scroll, and the
  quiet lets the lift go, half a second on, pulling nothing.
- **The hand, by hand tracking** (`tracksLiftedPinchByHand`): from the lift
  the item follows the hand whose pinch closed nearest its press
  (`PinchTracker`, `HandPinch`), its fingertips' midpoint placed on the
  item through its transform into the space, each move told to the pinch as
  the drag's would be, from where the hand stood at the lift; its fingers
  opening, or the hand lost three tenths of a second, are the drag's end.
  No gesture is involved, so nothing competes and nothing need be let in
  mid-pinch; it asks the person for hand tracking as the space opens, and
  needs it open. The drag is held back beneath it as above, and follows the
  pinch where the hand can't be followed. With the hand followed, a pinch's
  first 60 pt make no difference: its words come from the hand.
- **The drag from the touch**, at `dragStartDistance`, 15 pt, October 9's,
  to compare (`holdsDragBack` off).

Before the lift, with the drag held back, the hold is given up by the
scroll view: its phase, its offset moving a point, or the button's press it
cancels as it takes the pinch, its pan starting at about the hold's 10 pt
along the scroll; and by the drag's word at 60 pt, a move that far being a
scroll or a yank. A pinch moved across or toward the viewer by less than
60 pt before the quarter second now lifts its item; its pull counts from
the lift. Each pinch's trace says how it was followed: the drag's first word
after the lift, how long after it, how far from the touch, and whether its
start came down; the hand followed, which, and how near its pinch closed to
the press; and its last lines, how many words came after the lift, or none.
As the drag first speaks, a debug build's probe reads the scroll view's pan,
then again a moment later, so a pan failing in step with the drag shows.
`-labLoad lifted` pulls under each choice through the real adapters, the hand
by the hand tracker's stand-in.

## The lab

GestureLab, in `Lab/`, is a visionOS app: a window and a mixed immersive
space, opened at launch.

- **The window** lists the stations, each with a one-line summary. For the
  one chosen it shows the station's own window content (how to try it, and
  anything it shows as it's tried), its tuning panel, and its trace, with a
  switch that turns its tracing off; a switch in the toolbar turns the
  whole lab's off, both remembered.
- **A station's own window**, for a gesture that lives in a window, as an
  item in a scrolling grid does: the lab opens it beside its own as the
  station is chosen, with a button to open it again, and closes it as
  another is chosen. It shows the station's own window content edge to edge,
  with no scrolling column around it, and its trace in an ornament beside it,
  so the trace reads while the window is pinched.
- **The space** shows the chosen station's space content, a `RealityView`
  with attachments, standing around a point a meter ahead at about eye
  height (`LabSpace.front`), made afresh as another station is chosen.
- **A station** is a class conforming to `LabStation`: an id, a title, a
  summary, its window content, its space content, its tuning panels, and its
  `TraceRecorder`. Each area adds its station's files under
  `Lab/GestureLab/Stations/<Area>/` and one line to `LabStations.all()`; the
  app's sources are a synchronized folder, so new files never touch the
  project file. A station registers the RealityKit components and systems
  it uses in `registerComponents()`, which the app calls as it starts.
- **Trace check**, the starter station, proves the spine: a cube to pinch,
  each pinch traced from its touch to its release as a tap or a drag, its
  size tuned live.

### How tracing flows

A station hands its `TraceRecorder` to the adapters it uses. An adapter
begins an interaction as a pinch touches (`recorder?.begin("Pluck", title:
"Pinch on item 4")`), writes each thing that happens to the
`InteractionTrace` that gives it (`trace?.event("lift", "held still 0.50
s")`), and finishes it with its outcome (`trace?.finish("pull")`). The
recorder keeps the last 12 interactions, newest first (`TraceLog`). A run of
events of one name, one after another within a second, as a drag's words
come, folds into one line: how many, the first's and the latest's time and
detail, and the farthest any reached where the event gives a measure
(`TraceMeasure`); a change of name, a stage, always begins a line, and once
an interaction has ten lines a name it has had folds into that name's latest
line. The window's `TraceView` shows the newest two interactions in full and
the older ones in a line or two, white on black, sized so a screen recording
on the headset reads it, and each finished one's summary is logged at info
level, one line, for the console. The trace shows the log's changes at most
ten times a second (`TracePacing`), and lays itself out in the room it's
offered alone, so a gesture writing it as a hand moves draws nothing else
again:

    #3 Carry · Pinch on handle of panel-b → carried 0.42 m, 1.30 s: touch +0.00 s (carries after 8.0 pt); begin +0.05 s (after 9.5 pt, carries 'panel-b' from (0.00, 1.35, -1.00) m); carry ×5 +0.39–1.10 s (farthest 0.48 m; hand 0.10 m out, middle at (-0.05, 1.44, -1.00) m … hand 0.48 m out, middle at (0.38, 1.40, -1.00) m); release +1.30 s (released: …)

A recorder that isn't recording (`isRecording`) gives no trace from `begin`,
so an adapter handed it makes no title or detail and does no tracing work,
as one handed no recorder; the lab turns it off with a switch in its
window's toolbar, for the whole lab, or one in each trace's header, for its
station. Either way, the console gets at most one info line for each
finished interaction: the trace's summary when it's traced, and otherwise
the adapter's own line, if it has one for what happened; nothing is logged
at info for each word of a drag.

### How tuning flows

Each area's tuning conforms to `Tunable`: its defaults, and a
`TuningParameter` for each number or switch, with a key (the property's
name), a title, a unit, a range and a step, read and written through its key
path. The station keeps it in a `TuningStore`, which saves the values that
differ from the defaults in `UserDefaults` under "GestureLab.<station
id>", and shows a `TuningPanel`: a slider with its number for each number,
unstepped, its value fitted to the step as it's set, a switch for each
switch, Defaults, and Copy tuning. The station passes
`store.tuning` to its adapters as it reads them, so a slider's change takes
effect at once.

Once a tuning feels right on the headset, Copy tuning puts it on the
pasteboard as the Swift initializer that makes it, each changed value
marked with the default it replaces, and logs it. That goes into the area's
tuning as its new defaults, in a commit of its own, and every app on
GestureKit gets them as it updates.

## How Vignette adopts it

Vignette depends on GestureKit by URL, tracking `main` at first, then a
tagged release once the gestures settle. Area by area, it deletes its own
copies of the rules and adapters and calls GestureKit's instead, mapping its
own nouns onto GestureKit's neutral ones at the call site, passing the
default tunings unless it wants others, and no recorder outside its debug
builds. Its own tests of those rules go with them; GestureKit's cover them.

## Order

1. Carry, Facing, and Placement, with their stations.
2. Pluck, with its station.
3. Vignette adopts those.
4. Press, Coast, and HoldWatch, with their stations; then Vignette adopts
   them too.

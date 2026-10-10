import GestureKit
import RealityKit
import SwiftUI

/// A card for an item that broke free of the grid: which item, where it
/// stands in the space, and whether the pinch that spawned it has let go.
/// Where it stands is where it spawned, then where it was last let go: its
/// entity, which the carry moves, has it meanwhile, and the card keeps it
/// only for an entity made again, as the space opens again.
struct PluckLabCard: Identifiable, Equatable {
    let id: UUID
    let item: Int
    var standsAt: SIMD3<Float>
    var hasLanded: Bool
}

/// The pluck's station: a grid of numbered items in a window of its own, as
/// a library's, each pluckable, with nothing scrolling around it. A pinch
/// is its scroll unless it's a hold: one the grid scrolls with, whose
/// content moves at all, or that moves 10 pt up or down, is its scroll;
/// held still a quarter second, an item lifts and the scroll stops, until
/// the hand moves mostly up or down, which gives the pinch back to it; lifted, it follows the hand a little, held to its
/// place, until the hand has gone 2.5 cm, when it breaks free and spawns as
/// a card at the hand. From there the pluck's part is over: the same pinch
/// carries the card by the carry's own rules, 1:1, clear of the head, and
/// the card faces you through the facing system; once let go, it's carried
/// by the grab handle under it, as any carried panel.
/// Every pinch is traced, each word with why it did what it did, and the
/// grid's own scrolls apart, so one pinch's timeline says whether a scroll
/// lifted, how far the held item stretched, and when it broke free.
@MainActor @Observable
final class PluckStation: LabStation {
    let id = "pluck"
    let title = "Pluck"
    let summary = "Pull a numbered item out of a scrolling grid into the room."
    let tuning = TuningStore<PluckTuning>(namespace: "GestureLab.pluck")
    let carry = TuningStore<CarryTuning>(namespace: "GestureLab.pluck.carry")
    let trace = TraceRecorder(logsSummariesPublicly: true)

    /// The grid's container: the lifted item and the scroll's hold.
    let container = PluckContainerModel()

    /// The cards in the room, landed or still carried by the pinch that
    /// spawned them: the space makes an entity for each, and moves it
    /// through the carry, not through these, so the hand's steps change
    /// nothing observed. The windows read `cardCount`.
    private(set) var cards: [PluckLabCard] = [] {
        didSet {
            if cards.count != cardCount { cardCount = cards.count }
        }
    }

    /// How many cards are in the room, observed apart from the cards, so a
    /// card landing draws neither window again.
    private(set) var cardCount = 0

    /// Each card's entity, as the space made it.
    @ObservationIgnored private var entities: [UUID: Entity] = [:]

    /// Where the carry last put a card's middle before the space made its
    /// entity, which it stands there as it makes it.
    @ObservationIgnored private var carriedBeforeItsEntity: [UUID: SIMD3<Float>] = [:]

    /// The card each item's pinch carries, by the item's number, from its
    /// spawn until it's let go.
    @ObservationIgnored private var spawning: [Int: UUID] = [:]

    /// The last item tapped, and how many taps there have been.
    private(set) var lastTapped: Int?
    private(set) var taps = 0

    /// How many times the space has appeared, which the grid is made again
    /// for: in the simulator, a window view put on screen before the space
    /// opened gave its own coordinates for the space's.
    private(set) var spaceAppearances = 0

    /// How many items the grid holds: thirty rows of four at the window's
    /// size, about eleven windows' worth to scroll.
    let itemCount = 120

    let ownWindowTitle: String? = "grid window"

    static func registerComponents() {
        GrabHandle.registerComponents()
        FacesTheViewerSystem.registerComponentsAndSystem()
    }

    var windowContent: some View { PluckLabInstructions(station: self) }
    var ownWindowContent: some View { PluckLabGridWindow(station: self) }
    var spaceContent: some View { PluckLabSpace(station: self) }
    var tuningContent: some View {
        VStack(spacing: 0) {
            TuningPanel(tuning, title: "Pluck")
            TuningPanel(carry, title: "Carry, once it's out")
        }
    }

    /// Where a card spawns when the pluck couldn't say where: in front of
    /// the station, a little apart by item.
    private func fallbackPosition(for item: Int) -> SIMD3<Float> {
        LabSpace.front + SIMD3(Float(item % 4) * 0.12 - 0.18, 0, 0.2)
    }

    /// What happened to `item`, as its pluck says: a spawn makes its card,
    /// and from there the carry stands it.
    func handle(_ event: PluckEvent, item: Int) {
        switch event {
        case .tapped:
            lastTapped = item
            taps += 1
        case .spawned(let place):
            let card = PluckLabCard(id: UUID(), item: item, standsAt: place ?? fallbackPosition(for: item), hasLanded: false)
            cards.append(card)
            spawning[item] = card.id
        case .carried(let middle, _):
            guard let id = spawning[item] else { return }
            stand(id, carriedTo: middle)
        case .released(let place):
            guard let id = spawning.removeValue(forKey: item) else { return }
            if let place { stand(id, carriedTo: place) }
            if let index = cards.firstIndex(where: { $0.id == id }) {
                cards[index].hasLanded = true
                if let entity = entities[id] { cards[index].standsAt = entity.position }
            }
        case .spawnCancelled:
            if let id = spawning.removeValue(forKey: item) {
                cards.removeAll { $0.id == id }
            }
        case .lifted, .settled:
            break
        }
    }

    /// Stands card `id`'s entity carried by its middle to `middle`, in the
    /// space, by the carry's rule: clear of the head and facing it
    /// (`CarriedEntity.stand`). Before the space has made its entity, the
    /// place waits for it.
    private func stand(_ id: UUID, carriedTo middle: SIMD3<Float>) {
        guard let entity = entities[id] else {
            carriedBeforeItsEntity[id] = middle
            return
        }
        CarriedEntity.stand(entity, carriedTo: middle, facingHeadAt: HeadTracker.shared.viewerPosition(), tuning: carry.tuning)
    }

    /// Makes an entity under `root` for each card that has none, from its
    /// attachments in `attachments`: the card, its pill under it, the grab
    /// handle in front of the pill, and facing the viewer as the head moves,
    /// standing where the card stands, or where the carry has put it since;
    /// and takes away the entities of cards that went.
    func showCards(under root: Entity, attachments: RealityViewAttachments) {
        let shown = Set(cards.map(\.id))
        for (id, entity) in entities where !shown.contains(id) {
            entity.removeFromParent()
            entities[id] = nil
            carriedBeforeItsEntity[id] = nil
        }
        for card in cards where entities[card.id] == nil {
            guard let view = attachments.entity(for: card.id) else { continue }
            let entity = Entity()
            entity.name = card.id.uuidString
            entity.addChild(view)
            let rig = PanelHandleRig(under: entity, carrying: entity.name, panelHeight: PluckLabCardView.side)
            if let pill = attachments.entity(for: Self.pillID(of: card.id)) {
                rig.hang(pill: pill)
            }
            entity.components.set(FacesTheViewerComponent())
            root.addChild(entity)
            entity.position = card.standsAt
            entities[card.id] = entity
            stand(card.id, carriedTo: carriedBeforeItsEntity.removeValue(forKey: card.id) ?? card.standsAt)
        }
    }

    /// A card was let go by the grab handle under it: it stands where its
    /// entity does.
    func cardLetGo(_ entity: Entity) {
        guard let index = cards.firstIndex(where: { $0.id.uuidString == entity.name }) else { return }
        cards[index].standsAt = entity.position
    }

    /// The id of card `id`'s pill's attachment.
    static func pillID(of id: UUID) -> String { "\(id.uuidString)-pill" }

    /// Takes every card out of the room.
    func clearCards() {
        cards.removeAll()
        spawning.removeAll()
    }

    /// The space appeared: the grid is made again, so its items' geometry
    /// is the open space's.
    func spaceAppeared() {
        spaceAppearances += 1
    }

    /// The space went: its entities with it.
    func spaceDisappeared() {
        entities.removeAll()
        carriedBeforeItsEntity.removeAll()
    }
}

/// An item in the grid: a rounded square in its own color, its number large
/// in the middle.
private struct PluckLabItem: View {
    let number: Int

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(pluckLabColor(of: number))
            .overlay {
                Text("\(number)")
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 18, style: .continuous))
            .hoverEffect(.highlight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Item \(number)")
    }
}

/// An item's color, by its number, so neighbors differ.
private func pluckLabColor(of number: Int) -> Color {
    Color(hue: Double((number * 7) % 48) / 48, saturation: 0.55, brightness: 0.85)
}

/// What the cards in the room come to, in words.
@MainActor
private func pluckLabCardsText(_ station: PluckStation) -> String {
    switch station.cardCount {
    case 0: "No cards in the room"
    case 1: "1 card in the room"
    case let count: "\(count) cards in the room"
    }
}

/// The pluck's part of the lab's window: how to try it, and the cards.
private struct PluckLabInstructions: View {
    let station: PluckStation

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("The grid is in a window of its own, as a library's is, with the trace beside it. Scroll it: a pinch is the grid's scroll unless it's a hold, so a pinch that moves up or down even a little before the quarter second, or moves the grid at all, scrolls, however slowly it starts. Pinch an item and hold still a quarter second: it lifts, and the scroll stops. Move your hand across, toward you, or away and the lifted item follows a little, held to its place, pulling harder the farther you go; move it up or down instead and the item settles back and the pinch is the grid's scroll again. Let go now and it settles back. Go on, about 2.5 cm from where your hand was as it lifted, and it breaks free as a card at your hand. From there it's carried: it follows your hand 1:1, stops 30 cm from your head, faces you, and stays where you let go; later, carry it by the pill under it. The trace shows each pinch: why it stayed a scroll or lifted, how far the grid's content and your hand moved before the hold against what it allows, how far the held item stretched of what it needs to break free, the moment it broke free, and where it was let go. Whether the grid takes up a pinch given back to it, or does nothing until you let go, is what to watch; its switch in the tuning turns the give-back off.")
                .font(.system(size: 18))
            HStack(spacing: 16) {
                Text(pluckLabCardsText(station))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                Spacer()
                Button("Clear the room", systemImage: "trash") {
                    station.clearCards()
                }
                .disabled(station.cardCount == 0)
            }
        }
    }
}

/// The pluck's own window: the grid, edge to edge, in its own scroll view,
/// in as many columns as fit at 260 pt, 2 pt apart, as a library window's;
/// and below it, the cards and what was last tapped, in a view of their
/// own (`PluckLabGridStatus`), so a tap draws that again and not the grid.
private struct PluckLabGridWindow: View {
    let station: PluckStation

    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(1...station.itemCount, id: \.self) { number in
                    PluckLabItem(number: number)
                        .aspectRatio(1, contentMode: .fit)
                        .pluckable(number, title: "item \(number)") { event in
                            station.handle(event, item: number)
                        }
                }
            }
        }
        #if DEBUG
        .labLoadScrolls()
        #endif
        .pluckContainer(station.container, tuning: station.tuning.tuning, trace: station.trace, scrollAxes: .vertical)
        .ignoresSafeArea()
        .id(station.spaceAppearances)
        // Four columns at the least, as a library window's.
        .frame(minWidth: 4 * 260 + 3 * 2, minHeight: 500)
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
            PluckLabGridStatus(station: station)
        }
    }
}

/// Below the pluck's grid: the cards in the room, what was last tapped, and
/// Clear the room.
private struct PluckLabGridStatus: View {
    let station: PluckStation

    var body: some View {
        HStack(spacing: 20) {
            Text(pluckLabCardsText(station))
                .font(.system(size: 20, weight: .semibold).monospacedDigit())
            if let tapped = station.lastTapped {
                Text("Tapped item \(tapped) · \(station.taps)")
                    .font(.system(size: 18).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Button("Clear the room", systemImage: "trash") {
                station.clearCards()
            }
            .disabled(station.cardCount == 0)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .glassBackgroundEffect()
        .padding(.top, 16)
    }
}

/// The pluck's part of the space: each card that broke free of the grid,
/// carried by the pinch that spawned it, then by the grab handle under it,
/// facing the viewer as the head moves.
private struct PluckLabSpace: View {
    let station: PluckStation

    var body: some View {
        let cards = station.cards
        RealityView { content, _ in
            let root = Entity()
            root.name = "pluck-lab-cards"
            content.add(root)
        } update: { content, attachments in
            guard let root = content.entities.first(where: { $0.name == "pluck-lab-cards" }) else { return }
            station.showCards(under: root, attachments: attachments)
        } attachments: {
            ForEach(cards) { card in
                Attachment(id: card.id) {
                    PluckLabCardView(card: card)
                }
                Attachment(id: PluckStation.pillID(of: card.id)) {
                    PanelHandlePill(label: "Move card \(card.item)")
                }
            }
        }
        .grabHandlesCarryEntities(tuning: station.carry.tuning, recorder: station.trace) { entity in
            station.cardLetGo(entity)
        }
        .task {
            await HeadTracker.shared.start()
        }
        .onAppear { station.spaceAppeared() }
        .onDisappear { station.spaceDisappeared() }
    }
}

/// A card in the room: its item's color and number, faint while the pinch
/// that spawned it still carries it.
private struct PluckLabCardView: View {
    /// Its side, in points.
    static let side = 220.0

    let card: PluckLabCard

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(pluckLabColor(of: card.item))
            .overlay {
                Text("\(card.item)")
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: Self.side, height: Self.side)
            .opacity(card.hasLanded ? 1 : 0.7)
    }
}

import GestureKit
import RealityKit
import SwiftUI

/// A card for an item pulled out of the grid: which item, where it stands
/// in the space, and whether it has landed or is still on its way.
struct PluckLabCard: Identifiable, Equatable {
    let id: UUID
    let item: Int
    var position: SIMD3<Float>
    var hasLanded: Bool
}

/// The pluck's station: a grid of numbered items in a window of its own, as
/// a library's, each pluckable, with nothing scrolling around it. A pinch that moves first scrolls it; held
/// still, an item lifts and the scroll stops; a moment later, a pull toward
/// you takes it out as a card that stands in the room where it's let go.
/// Every pinch is traced, each word with why it did what it did, and the
/// grid's own scrolls apart, so one pinch's timeline says whether a scroll
/// lifted, whether the press went at the lift, and what the pull rule made
/// of each move.
@MainActor @Observable
final class PluckStation: LabStation {
    let id = "pluck"
    let title = "Pluck"
    let summary = "Pull a numbered item out of a scrolling grid into the room."
    let tuning = TuningStore<PluckTuning>(namespace: "GestureLab.pluck")
    let trace = TraceRecorder(logsSummariesPublicly: true)

    /// The grid's container: the lifted item and the scroll's hold.
    let container = PluckContainerModel()

    /// The cards in the room, landed or on their way.
    private(set) var cards: [PluckLabCard] = []

    /// The card each item's pull under way carries, by the item's number.
    @ObservationIgnored private var pulling: [Int: UUID] = [:]

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

    var windowContent: some View { PluckLabInstructions(station: self) }
    var ownWindowContent: some View { PluckLabGridWindow(station: self) }
    var spaceContent: some View { PluckLabSpace(station: self) }
    var tuningContent: some View { TuningPanel(tuning, title: "Pluck") }

    /// Where a card stands when a pull couldn't say where it is: in front of
    /// the station, a little apart by item.
    private func fallbackPosition(for item: Int) -> SIMD3<Float> {
        LabSpace.front + SIMD3(Float(item % 4) * 0.12 - 0.18, 0, 0.2)
    }

    /// What happened to `item`, as its pluck says.
    func handle(_ event: PluckEvent, item: Int) {
        switch event {
        case .tapped:
            lastTapped = item
            taps += 1
        case .pullBegan(let position):
            let card = PluckLabCard(id: UUID(), item: item, position: position ?? fallbackPosition(for: item), hasLanded: false)
            cards.append(card)
            pulling[item] = card.id
        case .pullMoved(let position):
            move(item, to: position, landing: false)
        case .pullEnded(let position):
            move(item, to: position, landing: true)
            pulling[item] = nil
        case .pullCancelled:
            if let id = pulling.removeValue(forKey: item) {
                cards.removeAll { $0.id == id }
            }
        case .lifted, .settled:
            break
        }
    }

    private func move(_ item: Int, to position: SIMD3<Float>?, landing: Bool) {
        guard let id = pulling[item], let index = cards.firstIndex(where: { $0.id == id }) else { return }
        if let position { cards[index].position = position }
        if landing { cards[index].hasLanded = true }
    }

    /// Takes every card out of the room.
    func clearCards() {
        cards.removeAll()
        pulling.removeAll()
    }

    /// The space appeared: the grid is made again, so its items' geometry
    /// is the open space's.
    func spaceAppeared() {
        spaceAppearances += 1
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
    switch station.cards.count {
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
            Text("The grid is in a window of its own, as a library's is, with the trace beside it. Scroll it: a pinch that moves first is its scroll. Pinch an item and hold still: it lifts, and the scroll stops. A moment later pull toward you, and it comes out as a card that stands where you let go. The trace shows each pinch, each word with why it did what it did, and each scroll of the grid.")
                .font(.system(size: 18))
            HStack(spacing: 16) {
                Text(pluckLabCardsText(station))
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                Spacer()
                Button("Clear the room", systemImage: "trash") {
                    station.clearCards()
                }
                .disabled(station.cards.isEmpty)
            }
        }
    }
}

/// The pluck's own window: the grid, edge to edge, in its own scroll view,
/// in as many columns as fit at 260 pt, 2 pt apart, as a library window's;
/// and below it, the cards and what was last tapped.
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
        .pluckContainer(station.container, tuning: station.tuning.tuning, trace: station.trace)
        .ignoresSafeArea()
        .id(station.spaceAppearances)
        // Four columns at the least, as a library window's.
        .frame(minWidth: 4 * 260 + 3 * 2, minHeight: 500)
        .ornament(attachmentAnchor: .scene(.bottom), contentAlignment: .top) {
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
                .disabled(station.cards.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .glassBackgroundEffect()
            .padding(.top, 16)
        }
    }
}

/// The pluck's part of the space: each card pulled out, standing where it
/// is, turned to face where a standing person's head would be.
private struct PluckLabSpace: View {
    let station: PluckStation

    /// Where the cards turn to face: above the space's origin, at a standing
    /// person's eyes.
    private static let viewer = SIMD3<Float>(0, 1.5, 0)

    var body: some View {
        let cards = station.cards
        RealityView { content, _ in
            let root = Entity()
            root.name = "pluck-lab-cards"
            content.add(root)
        } update: { content, attachments in
            guard let root = content.entities.first(where: { $0.name == "pluck-lab-cards" }) else { return }
            let shown = Set(cards.map { $0.id.uuidString })
            for child in Array(root.children) where !shown.contains(child.name) {
                child.removeFromParent()
            }
            for card in cards {
                guard let entity = attachments.entity(for: card.id) else { continue }
                entity.name = card.id.uuidString
                if entity.parent !== root { root.addChild(entity) }
                entity.position = card.position
                entity.orientation = Self.facingTheViewer(from: card.position)
            }
        } attachments: {
            ForEach(cards) { card in
                Attachment(id: card.id) {
                    PluckLabCardView(card: card)
                }
            }
        }
        .onAppear { station.spaceAppeared() }
    }

    /// Turned about the vertical to face the viewer from `position`.
    private static func facingTheViewer(from position: SIMD3<Float>) -> simd_quatf {
        let toward = viewer - position
        return simd_quatf(angle: atan2(toward.x, toward.z), axis: [0, 1, 0])
    }
}

/// A card in the room: its item's color and number, faint while its pull is
/// on its way.
private struct PluckLabCardView: View {
    let card: PluckLabCard

    var body: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(pluckLabColor(of: card.item))
            .overlay {
                Text("\(card.item)")
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 220, height: 220)
            .opacity(card.hasLanded ? 1 : 0.7)
    }
}

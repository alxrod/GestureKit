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

/// The pluck's station: a grid of numbered items in the window, as a
/// library's, each pluckable. A pinch that moves first scrolls it; held
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

    /// How many items the grid holds: twelve rows of four, enough to scroll
    /// well.
    let itemCount = 48

    var windowContent: some View { PluckLabWindow(station: self) }
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
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(hue: Double((number * 7) % 48) / 48, saturation: 0.55, brightness: 0.85))
            .overlay {
                Text("\(number)")
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: 14, style: .continuous))
            .hoverEffect(.highlight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Item \(number)")
    }
}

/// The pluck's part of the window: how to try it, the cards, and the grid.
private struct PluckLabWindow: View {
    let station: PluckStation

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Scroll the grid: a pinch that moves first is its scroll. Pinch an item and hold still: it lifts and the scroll stops. A moment later pull toward you, and it comes out as a card that stands where you let go. The trace shows each pinch, each word with why it did what it did.")
                .font(.system(size: 18))
            HStack(spacing: 16) {
                Text(cardsText)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                if let tapped = station.lastTapped {
                    Text("Tapped item \(tapped) · \(station.taps)")
                        .font(.system(size: 18).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Clear the room", systemImage: "trash") {
                    station.clearCards()
                }
                .disabled(station.cards.isEmpty)
            }
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
            .frame(height: 560)
            .clipShape(.rect(cornerRadius: 16))
            .pluckContainer(station.container, tuning: station.tuning.tuning, trace: station.trace)
            .id(station.spaceAppearances)
        }
    }

    private var cardsText: String {
        switch station.cards.count {
        case 0: "No cards in the room"
        case 1: "1 card in the room"
        case let count: "\(count) cards in the room"
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
            .fill(Color(hue: Double((card.item * 7) % 48) / 48, saturation: 0.55, brightness: 0.85))
            .overlay {
                Text("\(card.item)")
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
            }
            .frame(width: 220, height: 220)
            .opacity(card.hasLanded ? 1 : 0.7)
    }
}

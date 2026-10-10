// The README's code for Pluck, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import RealityKit
import SwiftUI

/// The cards in the room, one for each item pulled out of the grid.
@MainActor @Observable
final class PluckedCards {
    /// Add it to the immersive space's content, at the space's origin.
    let root = Entity()
    @ObservationIgnored private var carried: [Int: Entity] = [:]

    func handle(_ event: PluckEvent, item: Int) {
        switch event {
        case .spawned(let place):
            // The pluck's part ends here: make what the item pulls out.
            let card = ModelEntity(
                mesh: .generateBox(width: 0.2, height: 0.2, depth: 0.01),
                materials: [SimpleMaterial(color: .systemTeal, isMetallic: false)]
            )
            card.name = "card \(item)"
            card.position = place ?? [0, 1.3, -0.8]
            root.addChild(card)
            carried[item] = card
        case .carried(let middle, _):
            // The same pinch carries it, by Carry's rules: 1:1 with the
            // hand, clear of the head, facing it.
            guard let card = carried[item] else { return }
            CarriedEntity.stand(card, carriedTo: middle, facingHeadAt: HeadTracker.shared.viewerPosition())
        case .released:
            // Let go, it's the app's: a grab handle carries it from now on.
            guard let card = carried.removeValue(forKey: item) else { return }
            let handle = GrabHandle.make(carrying: card.name, size: [0.15, 0.025])
            handle.position.y = -0.13
            card.addChild(handle)
            card.components.set(FacesTheViewerComponent())
        case .spawnCancelled:
            carried.removeValue(forKey: item)?.removeFromParent()
        case .tapped, .lifted, .settled:
            break
        }
    }
}

/// A window's grid of items, each pulled out into the room by a pinch held
/// still a quarter second; a pinch that moves first scrolls.
struct PluckGridView: View {
    let cards: PluckedCards
    @State private var container = PluckContainerModel()

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 4)], spacing: 4) {
                ForEach(1...60, id: \.self) { item in
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.teal)
                        .overlay { Text("\(item)").font(.largeTitle) }
                        .hoverEffect()
                        .aspectRatio(1, contentMode: .fit)
                        .pluckable(item, title: "item \(item)") { event in
                            cards.handle(event, item: item)
                        }
                }
            }
        }
        .pluckContainer(container)
    }
}

/// The room the cards stand in, each carried by its grab handle once let go.
struct PluckedCardsSpace: View {
    let cards: PluckedCards

    var body: some View {
        RealityView { content in
            content.add(cards.root)
        }
        .grabHandlesCarryEntities()
    }
}

// The README's code for Carry, through the app's own state, compiled with
// the lab so it can't rot. ReadmeSnippetsTests checks the README shows
// exactly the code below.

import GestureKit
import RealityKit
import SwiftUI

/// Marks the handles of boards whose places the app keeps. Register it at
/// launch, as `BoardHandle.registerComponent()`.
struct BoardHandle: Component {
    var board: Int
}

@MainActor @Observable
final class Boards {
    var middles: [Int: SIMD3<Float>] = [1: [-0.4, 1.3, -1], 2: [0.4, 1.3, -1]]
}

struct BoardsView: View {
    let boards: Boards

    var body: some View {
        RealityView { content in
            for (board, middle) in boards.middles {
                let entity = ModelEntity(mesh: .generatePlane(width: 0.4, height: 0.3), materials: [SimpleMaterial()])
                entity.name = "board \(board)"
                entity.position = middle
                let handle = GrabHandle.make(named: "handle", size: [0.2, 0.025], marking: BoardHandle(board: board))
                handle.position.y = -0.18
                entity.addChild(handle)
                content.add(entity)
            }
        } update: { content in
            for (board, middle) in boards.middles {
                content.entities.first { $0.name == "board \(board)" }?.position = middle
            }
        }
        .grabHandleCarry(
            of: BoardHandle.self,
            grab: { handle -> CarryPinch<Int>.Grabbed? in
                guard let board = handle.components[BoardHandle.self]?.board,
                      let middle = boards.middles[board] else { return nil }
                return CarryPinch.Grabbed(id: board, middle: middle)
            },
            onCarry: { step in
                // Where the hand puts it, but never nearer the head than 0.3 m.
                let head = HeadTracker.shared.viewerPosition() ?? UntrackedHead.eye
                let before = boards.middles[step.id] ?? step.middle
                boards.middles[step.id] = HandCarry.middle(carriedTo: step.middle, clearOf: head, from: before)
            }
        )
    }
}

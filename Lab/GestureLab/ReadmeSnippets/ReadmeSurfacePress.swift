// The README's code for Surface press, compiled with the lab so it can't
// rot. ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import SwiftUI

/// A bar where a tap drops a mark, a drag along moves the playhead, and a
/// hold of a second flags it; a drag across does nothing.
struct MarkingBar: View {
    @Environment(\.physicalMetrics) private var metrics
    /// Meters from the bar's leading edge, as the press gives places along it.
    @State private var playhead = 0.0
    @State private var marks: [Double] = []
    @State private var isFlagged = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isFlagged ? Color.orange : Color.gray)
            .frame(width: metrics.convert(0.8, from: .meters), height: 80)
            .overlay(alignment: .leading) {
                ForEach(marks.indices, id: \.self) { index in
                    Circle()
                        .fill(.cyan)
                        .frame(width: 16, height: 16)
                        .offset(x: metrics.convert(marks[index], from: .meters) - 8)
                }
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 4)
                    .offset(x: metrics.convert(playhead, from: .meters) - 2)
            }
            .surfacePress(canHold: true, canPickUp: false) { event in
                switch event.action {
                case .tap(let along):
                    marks.append(along)
                case .beginDragAlong(_, let along), .moveDragAlong(let along):
                    playhead = along
                case .fireHold:
                    isFlagged.toggle()
                default:
                    break
                }
            }
    }
}

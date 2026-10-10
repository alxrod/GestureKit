// The README's code for Hold watch, compiled with the lab so it can't rot.
// ReadmeSnippetsTests checks the README shows exactly the code below.

import GestureKit
import SwiftUI

/// A handle whose own drag resizes something, and whose still hold asks a
/// question instead, its drag and tap doing nothing for the rest of the
/// pinch.
struct ResizeHandle: View {
    @Binding var width: Double
    @State private var isHeld = false
    @State private var asksToSplit = false
    @State private var widthAtStart: Double?
    @GestureState private var isDragging = false

    var body: some View {
        Capsule()
            .fill(isHeld ? Color.orange : Color.yellow)
            .frame(width: 44, height: 136)
            .gesture(
                DragGesture(minimumDistance: 15)
                    .updating($isDragging) { _, dragging, _ in dragging = true }
                    .onChanged { value in
                        guard !isHeld else { return }
                        let start = widthAtStart ?? width
                        widthAtStart = start
                        width = max(start + value.translation.width, 100)
                    }
                    .onEnded { _ in widthAtStart = nil }
            )
            .holdWatch(isHeld: $isHeld, dragHasBegun: isDragging) {
                asksToSplit = true
                return true
            }
            .alert("Split here?", isPresented: $asksToSplit) {
                Button("Split") {}
                Button("Cancel", role: .cancel) {}
            }
    }
}

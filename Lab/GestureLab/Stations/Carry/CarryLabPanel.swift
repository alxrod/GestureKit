import SwiftUI

/// A panel the carry stations stand in the space: a title and a line on
/// glass, and whatever else a station puts under them, telling the station
/// how tall it lays out, so the handle under it stands just below its edge.
struct CarryLabPanel<Extra: View>: View {
    let title: String
    let detail: String
    let resized: (Double) -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
            Text(detail)
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            extra
        }
        .padding(28)
        .frame(width: 420, alignment: .leading)
        .glassBackgroundEffect(in: .rect(cornerRadius: 28))
        .onGeometryChange(for: Double.self) { geometry in
            Double(geometry.size.height)
        } action: { height in
            resized(height)
        }
    }
}

extension CarryLabPanel where Extra == EmptyView {
    init(title: String, detail: String, resized: @escaping (Double) -> Void) {
        self.init(title: title, detail: detail, resized: resized) { EmptyView() }
    }
}

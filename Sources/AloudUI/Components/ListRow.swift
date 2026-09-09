import SwiftUI

public struct ListRow: View {
    public let title: String
    public let status: String
    public let symbol: String
    public init(title: String, status: String, symbol: String) {
        self.title = title
        self.status = status
        self.symbol = symbol
    }
    public var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).foregroundStyle(Ink.soft).accessibilityHidden(true)
            Text(title).font(Type.cardTitle).lineLimit(Type.singleLine)
            Spacer()
            Text(status).font(Type.caption).foregroundStyle(Ink.soft)
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.isEmpty ? title : "\(title), \(status)")
    }
}

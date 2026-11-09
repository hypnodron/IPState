import SwiftUI
import IPStateCore

struct MenuBarStatusLabel: View {
    let title: String
    let condition: NetworkCondition
    let isStale: Bool

    var body: some View {
        Text(title)
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: 20)
            .opacity(condition.symbol == nil ? 1 : 0)
            .overlay {
                if let symbol = condition.symbol {
                    Image(systemName: symbol).font(.system(size: 12))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isStale, condition == .online {
                    Circle().fill(.secondary).frame(width: 3, height: 3)
                }
            }
            .help(condition.description + (isStale ? " · last known result" : ""))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("IP State: \(condition.description). \(title)")
    }
}

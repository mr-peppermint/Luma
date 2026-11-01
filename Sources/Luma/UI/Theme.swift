import SwiftUI

enum Theme {
    static let accent = Color(red: 0.35, green: 0.39, blue: 0.96)
    static let accentLight = Color(red: 0.56, green: 0.59, blue: 1)

    static func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct PillBadge: View {
    let text: String
    var tint: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .tracking(0.7)
            .foregroundStyle(tint.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
    }
}

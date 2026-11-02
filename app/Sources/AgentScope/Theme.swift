import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0E0D14)
    static let panel = Color(hex: 0x17151F)
    static let stroke = Color(hex: 0x2A2738)
    static let text = Color(hex: 0xF3F1FA)
    static let body = Color(hex: 0xB8B3C9)
    static let muted = Color(hex: 0x8C879E)
    static let accent = Color(hex: 0x9D85FF)
    static let accentDeep = Color(hex: 0x5B3FD9)
    static let warm = Color(hex: 0xF2B35B)
    static let hot = Color(hex: 0xE5675B)

    // Token mix colours: told apart by lightness as well as hue.
    static let cacheRead = Color(hex: 0xD9D0FF)
    static let cacheWrite = Color(hex: 0x4FB8A8)
    static let freshInput = Color(hex: 0x8B6CFF)
    static let output = Color(hex: 0x4A3A99)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum Format {
    /// 709k, 3.4M, 18.2B; "—" when the value was never reported.
    static func tokens(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch abs(value) {
        case 1_000_000_000...: return String(format: "%.1fB", value / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", value / 1_000_000)
        case 10_000...: return String(format: "%.0fk", value / 1_000)
        case 1_000...: return String(format: "%.1fk", value / 1_000)
        default: return String(format: "%.0f", value)
        }
    }

    static func usd(_ value: Double?) -> String {
        guard let value else { return "—" }
        switch value {
        case 0: return "$0"
        case ..<0.01: return String(format: "$%.4f", value)
        case ..<1: return String(format: "$%.3f", value)
        default: return String(format: "$%.2f", value)
        }
    }

    static func percent(_ part: Double?, of whole: Double?) -> String {
        guard let part, let whole, whole > 0 else { return "—" }
        let p = part / whole * 100
        return p > 0 && p < 0.1 ? "<0.1%" : String(format: "%.1f%%", p)
    }

    static func shortID(_ id: String) -> String { String(id.prefix(8)) }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(Theme.muted)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
    }
}

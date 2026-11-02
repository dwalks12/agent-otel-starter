import SwiftUI

enum Theme {
    static let background = Color(hex: 0x0E0D14)
    static let sidebar = Color(hex: 0x111019)
    static let panel = Color(hex: 0x17151F)
    static let panelRaised = Color(hex: 0x1D1A28)
    static let stroke = Color(hex: 0x2A2738)
    static let text = Color(hex: 0xF3F1FA)
    static let body = Color(hex: 0xB8B3C9)
    static let muted = Color(hex: 0x8C879E)
    static let accent = Color(hex: 0x9D85FF)
    static let accentDeep = Color(hex: 0x5B3FD9)
    static let warm = Color(hex: 0xF2B35B)
    static let hot = Color(hex: 0xE5675B)
    static let good = Color(hex: 0x4FB8A8)

    // Token mix colours: told apart by lightness as well as hue.
    static let cacheRead = Color(hex: 0xD9D0FF)
    static let cacheWrite = Color(hex: 0x4FB8A8)
    static let freshInput = Color(hex: 0x8B6CFF)
    static let output = Color(hex: 0x4A3A99)

    /// A stable colour per model family, used for chips and dots.
    static func model(_ name: String) -> Color {
        let n = name.lowercased()
        if n.contains("opus") { return accent }
        if n.contains("sonnet") { return good }
        if n.contains("haiku") { return warm }
        if n.contains("gpt") || n.contains("codex") { return Color(hex: 0x6FA8FF) }
        return muted
    }

    static let cardBorder = LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                                           startPoint: .top, endPoint: .bottom)
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

    /// 4 ms, 812 ms, 8.4 s, 2m 05s
    static func duration(ms: Double) -> String {
        switch ms {
        case ..<1000: return String(format: "%.0f ms", ms)
        case ..<60_000: return String(format: "%.1f s", ms / 1000)
        default: return String(format: "%dm %02ds", Int(ms / 60_000), Int(ms / 1000) % 60)
        }
    }

    /// 42s, 3m 40s, 1h 05m
    static func span(seconds: Double) -> String {
        let s = Int(max(0, seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return String(format: "%dm %02ds", s / 60, s % 60) }
        return String(format: "%dh %02dm", s / 3600, s / 60 % 60)
    }

    /// "opus 5.5" from "claude-opus-5-5"
    static func modelName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "claude-", with: "")
        if let range = name.range(of: #"-(\d+)-(\d+)$"#, options: .regularExpression) {
            let version = name[range].dropFirst().replacingOccurrences(of: "-", with: ".")
            name = name[..<range.lowerBound] + " " + version
        }
        return name
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}

/// A raised card with a soft top highlight.
struct Panel<Content: View>: View {
    var title: String?
    var icon: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 6) {
                    if let icon { Image(systemName: icon).font(.system(size: 10, weight: .bold)) }
                    Text(title.uppercased())
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(Theme.muted)
            }
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.panelRaised, Theme.panel], startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

/// A segmented control drawn as pills, with a sliding selection.
struct PillTabs<Value: Hashable>: View {
    var options: [(Value, String)]
    @Binding var selection: Value
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = value }
                } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selection == value ? Theme.text : Theme.muted)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background {
                            if selection == value {
                                Capsule().fill(Theme.accentDeep.opacity(0.85))
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.background.opacity(0.6), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// A small coloured chip naming a model.
struct ModelChip: View {
    var model: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.model(model)).frame(width: 6, height: 6)
            Text(Format.modelName(model))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.model(model))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.model(model).opacity(0.12), in: Capsule())
    }
}

/// An on/off filter drawn as a chip.
struct FilterChip: View {
    var title: String
    var icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isOn ? Theme.text : Theme.muted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isOn ? Theme.accentDeep.opacity(0.35) : Color.clear, in: Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Theme.accent.opacity(0.5) : Theme.stroke))
        }
        .buttonStyle(.plain)
    }
}

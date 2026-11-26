import AppKit
import SwiftUI

/// Every tool call or reply, across all sessions, that touched something on the watchlist, and the list itself.
struct WatchlistPage: View {
    var watchlist: Watchlist
    var hits: [WatchHit]
    var titles: [String: String]
    var open: (String) -> Void

    private var blocked: Int { hits.filter { if case .blocked = $0.outcome { true } else { false } }.count }
    private var hitsByRule: [String: Int] {
        hits.reduce(into: [:]) { counts, hit in for rule in hit.rules { counts[rule.id, default: 0] += 1 } }
    }

    /// "now", "4m ago", "2h ago", "3d ago": short enough for the time column.
    static func ago(_ date: Date) -> String {
        let s = Int(max(0, Date.now.timeIntervalSince(date)))
        return switch s {
        case ..<60: "now"
        case ..<3600: "\(s / 60)m ago"
        case ..<86_400: "\(s / 3600)h ago"
        default: "\(s / 86_400)d ago"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Fact(icon: "exclamationmark.shield.fill", tint: Theme.hot, label: "Hits", value: "\(hits.count)", note: "last 7 days")
                Fact(icon: "bubble.left.and.text.bubble.right.fill", tint: Theme.accent, label: "Sessions",
                     value: "\(Set(hits.map(\.sessionID)).count)", note: "touched something on the list")
                Fact(icon: "hand.raised.fill", tint: Theme.good, label: "Blocked", value: "\(blocked)", note: "stopped before they ran")
                Fact(icon: "binoculars.fill", tint: Theme.warm, label: "Rules", value: "\(watchlist.rules.count)", note: "in watchlist.json")
            }
            .fixedSize(horizontal: false, vertical: true)

            Panel(title: "Hits · last 7 days", icon: "exclamationmark.shield.fill") {
                if hits.isEmpty {
                    Text(watchlist.rules.isEmpty ? "Add rules to watchlist.json and matching tool calls show up here."
                                                 : "No agent has touched anything on the list in the last 7 days.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                }
                LazyVStack(spacing: 8) {
                    ForEach(hits) { hit in
                        Button { open(hit.sessionID) } label: {
                            WatchHitRow(hit: hit, time: Self.ago(hit.date),
                                        session: titles[hit.sessionID] ?? "Session \(Format.shortID(hit.sessionID))")
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Panel(title: "On the list", icon: "binoculars.fill") {
                HStack(spacing: 10) {
                    Text(watchlist.url.path).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.body)
                        .lineLimit(1).truncationMode(.head).textSelection(.enabled)
                    Spacer(minLength: 8)
                    Text("Changes load within 2 seconds").font(.system(size: 11)).foregroundStyle(Theme.muted)
                    Button { NSWorkspace.shared.open(watchlist.url) } label: {
                        Label("Open watchlist.json", systemImage: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Theme.accentDeep.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!FileManager.default.fileExists(atPath: watchlist.url.path))
                }
                if let error = watchlist.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.warm)
                }
                ForEach(WatchRule.Kind.allCases) { kind in
                    let rules = watchlist.rules.filter { $0.kind == kind }
                    if !rules.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Image(systemName: kind.icon).font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.hot)
                                Text(kind.title.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2)
                                    .foregroundStyle(Theme.muted)
                                Text("matched \(kind.how)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                            }
                            ForEach(rules) { rule in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(rule.match).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                                        .lineLimit(1).truncationMode(.middle).frame(width: 220, alignment: .leading)
                                        .textSelection(.enabled)
                                    Text(rule.why).font(.system(size: 12)).foregroundStyle(Theme.body).lineLimit(2)
                                    Spacer(minLength: 8)
                                    if let count = hitsByRule[rule.id] {
                                        Text("\(count) hit\(count == 1 ? "" : "s")").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.hot)
                                    }
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
    }
}

/// One watchlist hit: when, what ran, which rules it matched, and how it ended.
struct WatchHitRow: View {
    var hit: WatchHit
    var time: String
    /// The session's title, on pages that list hits from more than one session.
    var session: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(time).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                    .lineLimit(1).frame(width: 64, alignment: .trailing)
                if let tool = hit.tool {
                    ToolIcon(name: tool)
                } else {
                    Image(systemName: "sparkles").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.accent)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                Text(hit.tool ?? "Reply").font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                Text(hit.summary).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.body)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 8)
                WatchOutcomePill(outcome: hit.outcome)
            }
            HStack(spacing: 6) {
                ForEach(hit.rules) { WatchRulePill(rule: $0) }
                Text(hit.rules.first?.why ?? "").font(.system(size: 12)).foregroundStyle(Theme.body).lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                if let session {
                    Text(session).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 280, alignment: .trailing)
                }
            }
            .padding(.leading, 74)
        }
        .padding(12)
        .background(Theme.hot.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hot.opacity(0.22)))
    }
}

/// The rule a call matched, e.g. "webhook.site", with the reason on hover.
struct WatchRulePill: View {
    var rule: WatchRule

    var body: some View {
        Label(rule.match, systemImage: rule.kind.icon)
            .font(.system(size: 11, weight: .semibold)).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(Theme.hot).background(Theme.hot.opacity(0.14), in: Capsule())
            .help(rule.why)
    }
}

struct WatchOutcomePill: View {
    var outcome: WatchHit.Outcome

    private var label: (text: String, color: Color) {
        switch outcome {
        case .ran: ("ran", Theme.warm)
        case .failed: ("ran · failed", Theme.warm)
        case .waiting: ("no result yet", Theme.muted)
        case .said: ("in Claude’s reply", Theme.accent)
        case .blocked(let source): ("blocked" + (source.map { " · " + $0.replacingOccurrences(of: "_", with: " ") } ?? ""), Theme.good)
        }
    }

    var body: some View {
        Text(label.text).font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(label.color).background(label.color.opacity(0.15), in: Capsule())
    }
}

/// A banner for a hit in the last 15 minutes, shown on every page until dismissed.
struct WatchAlert: View {
    var hit: WatchHit
    var session: String
    var open: () -> Void
    var dismiss: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill").font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.hot)
            VStack(alignment: .leading, spacing: 4) {
                Text("On your watchlist: " + hit.rules.map(\.match).joined(separator: ", "))
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("\(hit.tool ?? "Claude’s reply") · \(hit.summary)")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.body).lineLimit(1).truncationMode(.tail)
                Text("\(session) · \(Format.relative(hit.date))").font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 12)
            Button(action: open) {
                Text("Open session").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.hot.opacity(0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(14)
        .background(Theme.hot.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.hot.opacity(0.45)))
    }
}

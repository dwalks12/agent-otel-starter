import SwiftUI

struct SessionDetail: View {
    var session: SessionRow
    var models: [ModelRow]
    var commits: [CommitRow]

    var body: some View {
        Panel(title: "Session \(Format.shortID(session.sessionID))") {
            HStack(alignment: .top, spacing: 28) {
                fact("Spend", Format.usd(session.usage.usd))
                fact("Tokens", Format.tokens(session.usage.totalTokens))
                fact("Model calls", "\(session.usage.calls)")
                fact("Started", session.startedAt.formatted(date: .abbreviated, time: .shortened))
                fact("Active for", Duration.seconds(session.lastSeen - session.started)
                    .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
                if !commits.isEmpty {
                    fact("Per commit", Format.usd(session.usage.usd.map { $0 / Double(commits.count) }), note: "session ÷ commits")
                }
            }
            if session.usage.unpriced > 0 {
                Text("\(session.usage.unpriced) calls reported no cost; they are left out of the spend, not counted as $0.")
                    .font(.system(size: 12)).foregroundStyle(Theme.warm)
            }

            Divider().overlay(Theme.stroke)
            Text("MODELS").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.muted)
            Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 8) {
                GridRow {
                    ForEach(["Model", "Calls", "Input", "Output", "Cache read", "Cache write", "Spend"], id: \.self) {
                        Text($0).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                    }
                }
                ForEach(models) { row in
                    GridRow {
                        Text(row.model).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.text)
                        Text("\(row.usage.calls)")
                        Text(Format.tokens(row.usage.input))
                        Text(Format.tokens(row.usage.output))
                        Text(Format.tokens(row.usage.cacheRead))
                        Text(Format.tokens(row.usage.cacheWrite))
                        Text(Format.usd(row.usage.usd)).foregroundStyle(Theme.text)
                    }
                    .monospacedDigit().foregroundStyle(Theme.body)
                }
            }

            Divider().overlay(Theme.stroke)
            Text("COMMITS").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.muted)
            if commits.isEmpty {
                Text("No stamped commits yet. Install the hooks with scripts/install-hooks.sh, then commit from that repo.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
            } else {
                ForEach(commits) { commit in
                    HStack(spacing: 12) {
                        Text(String(commit.sha.prefix(8))).font(.system(.body, design: .monospaced)).foregroundStyle(Theme.accent)
                        Text(commit.subject).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        Text(commit.repo).foregroundStyle(Theme.muted)
                        Text("+\(commit.insertions) −\(commit.deletions)").monospacedDigit().foregroundStyle(Theme.body)
                        Text(Format.relative(commit.date)).foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 13))
                }
            }
        }
    }

    private func fact(_ label: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.muted)
            Text(value).font(.system(size: 18, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
            if let note { Text(note).font(.system(size: 10)).foregroundStyle(Theme.muted) }
        }
    }
}

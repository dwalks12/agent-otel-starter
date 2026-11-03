import SwiftUI

struct SessionDetail: View {
    var session: SessionRow
    var models: [ModelRow]
    var commits: [CommitRow]
    var transcript: [TranscriptItem]

    enum Tab: Hashable { case transcript, tools, models, commits }

    @State private var tab: Tab = .transcript
    @State private var showRequests = true
    @State private var showSystem = false

    private var toolStats: [ToolStat] { ToolStat.from(transcript) }
    private var toolCalls: Int { toolStats.reduce(0) { $0 + $1.calls } }
    private var toolFailures: Int { toolStats.reduce(0) { $0 + $1.failures } }
    private var prompts: Int { transcript.filter { if case .prompt = $0.kind { true } else { false } }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            hero
            factGrid
            if session.usage.unpriced > 0 {
                Label("\(session.usage.unpriced) calls reported no cost. They are left out of the spend, not counted as $0.",
                      systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.warm)
            }
            Panel {
                PillTabs(options: [(.transcript, "Transcript"), (.tools, "Tools · \(toolCalls)"),
                                   (.models, "Models · \(models.count)"), (.commits, "Commits · \(commits.count)")],
                         selection: $tab)
                switch tab {
                case .transcript: transcriptView
                case .tools: toolsView
                case .models: modelsView
                case .commits: commitsView
                }
            }
        }
    }

    // MARK: Header

    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ForEach(session.modelList, id: \.self) { ModelChip(model: $0) }
                Text(Format.shortID(session.sessionID))
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                    .textSelection(.enabled)
            }
            Text(session.title ?? "Untitled session")
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(3)
                .textSelection(.enabled)
            Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened)) · active for \(Format.span(seconds: session.lastSeen - session.started))")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }

    private var factGrid: some View {
        HStack(spacing: 12) {
            Fact(icon: "dollarsign", tint: Theme.warm, label: "Spend", value: Format.usd(session.usage.usd),
                 note: commits.isEmpty ? nil : "\(Format.usd(session.usage.usd.map { $0 / Double(commits.count) })) per commit")
            Fact(icon: "circle.hexagongrid.fill", tint: Theme.accent, label: "Tokens", value: Format.tokens(session.usage.totalTokens),
                 note: "\(Format.percent(session.usage.cacheRead, of: session.usage.totalTokens)) cache")
            Fact(icon: "person.fill", tint: Theme.cacheRead, label: "Prompts", value: "\(prompts)", note: nil)
            Fact(icon: "arrow.up.arrow.down", tint: Theme.body, label: "Model calls", value: "\(session.usage.calls)", note: nil)
            Fact(icon: "wrench.and.screwdriver.fill", tint: Theme.good, label: "Tool calls", value: "\(toolCalls)",
                 note: toolFailures > 0 ? "\(toolFailures) failed" : nil, noteTint: Theme.hot)
            Fact(icon: "arrow.triangle.branch", tint: Theme.warm, label: "Commits", value: "\(commits.count)", note: nil)
        }
    }

    // MARK: Transcript

    private var transcriptView: some View {
        let start = transcript.first?.date ?? session.startedAt
        let visible = transcript.filter { item in
            if item.isSystem { return showSystem }
            if case .request = item.kind { return showRequests }
            return true
        }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                FilterChip(title: "Model calls", icon: "arrow.up.arrow.down", isOn: $showRequests)
                FilterChip(title: "Hooks and plugins", icon: "puzzlepiece.extension", isOn: $showSystem)
                Spacer()
                Text("\(visible.count) of \(transcript.count) events")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
            }
            if transcript.isEmpty {
                Text("No events for this session yet.").foregroundStyle(Theme.muted).padding(.vertical, 8)
            }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, item in
                    TimelineRow(item: item, offset: offset(item.date, from: start), isLast: index == visible.count - 1)
                }
            }
        }
    }

    private func offset(_ date: Date, from start: Date) -> String {
        let s = max(0, Int(date.timeIntervalSince(start)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: Tools

    private var toolsView: some View {
        let maxCalls = max(1, toolStats.map(\.calls).max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            if toolStats.isEmpty { Text("No tool calls in this session.").foregroundStyle(Theme.muted) }
            ForEach(toolStats) { stat in
                HStack(spacing: 14) {
                    ToolIcon(name: stat.name)
                    Text(stat.name).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                        .frame(width: 110, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule().fill(Theme.stroke.opacity(0.6))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.good.gradient)
                                    .frame(width: proxy.size.width * Double(stat.calls) / Double(maxCalls))
                            }
                    }
                    .frame(height: 6)
                    Text("\(stat.calls) calls").frame(width: 70, alignment: .trailing)
                    Text(stat.failures > 0 ? "\(stat.failures) failed" : "—").foregroundStyle(stat.failures > 0 ? Theme.hot : Theme.muted)
                        .frame(width: 70, alignment: .trailing)
                    Text(stat.rejected > 0 ? "\(stat.rejected) rejected" : "—").foregroundStyle(stat.rejected > 0 ? Theme.warm : Theme.muted)
                        .frame(width: 84, alignment: .trailing)
                    Text(stat.calls > 0 ? "avg \(Format.duration(ms: stat.totalMs / Double(stat.calls)))" : "—")
                        .frame(width: 90, alignment: .trailing)
                }
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(Theme.body)
            }
        }
    }

    // MARK: Models and commits

    private var modelsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(models) { row in
                HStack(alignment: .firstTextBaseline, spacing: 22) {
                    ModelChip(model: row.model).frame(width: 130, alignment: .leading)
                    metric("calls", "\(row.usage.calls)")
                    metric("input", Format.tokens(row.usage.input))
                    metric("output", Format.tokens(row.usage.output))
                    metric("cache read", Format.tokens(row.usage.cacheRead))
                    metric("cache write", Format.tokens(row.usage.cacheWrite))
                    Spacer()
                    Text(Format.usd(row.usage.usd)).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(Theme.text)
                }
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 14, weight: .medium, design: .monospaced)).foregroundStyle(Theme.text)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var commitsView: some View {
        if commits.isEmpty {
            Label("No stamped commits yet. Install the hooks with scripts/install-hooks.sh, then commit from that repo.",
                  systemImage: "arrow.triangle.branch")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
        } else {
            VStack(spacing: 8) {
                ForEach(commits) { commit in
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch").foregroundStyle(Theme.warm)
                        Text(String(commit.sha.prefix(8))).font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.accent)
                        Text(commit.subject).foregroundStyle(Theme.text).lineLimit(1)
                        Spacer()
                        Text(commit.repo).foregroundStyle(Theme.muted)
                        Text("+\(commit.insertions)").foregroundStyle(Theme.good)
                        Text("−\(commit.deletions)").foregroundStyle(Theme.hot)
                        Text(Format.relative(commit.date)).foregroundStyle(Theme.muted)
                    }
                    .font(.system(size: 13)).monospacedDigit()
                    .padding(12)
                    .background(Theme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }
}

struct Fact: View {
    var icon: String
    var tint: Color
    var label: String
    var value: String
    var note: String?
    var noteTint: Color = Theme.muted

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                Text(label.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1)
                    .foregroundStyle(Theme.muted)
            }
            Text(value).font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.text)
            Text(note ?? " ").font(.system(size: 11)).foregroundStyle(noteTint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint.opacity(0.09), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

/// A coloured square with an icon for each tool.
struct ToolIcon: View {
    var name: String

    private var symbol: String {
        switch name {
        case "Bash": "terminal.fill"
        case "Read", "NotebookRead": "doc.text.fill"
        case "Edit", "MultiEdit", "NotebookEdit": "pencil"
        case "Write": "square.and.pencil"
        case "Grep", "Glob": "magnifyingglass"
        case "WebFetch", "WebSearch": "globe"
        case "Task", "Agent": "person.2.fill"
        case "TodoWrite": "checklist"
        default: name.hasPrefix("mcp__") ? "puzzlepiece.extension.fill" : "wrench.and.screwdriver.fill"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.good)
            .frame(width: 26, height: 26)
            .background(Theme.good.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// One step on the session timeline: time, a node on the rail, and the event.
struct TimelineRow: View {
    var item: TranscriptItem
    var offset: String
    var isLast: Bool

    private var node: (icon: String, tint: Color, size: CGFloat) {
        switch item.kind {
        case .prompt: ("person.fill", Theme.accent, 26)
        case .response: ("sparkles", Theme.good, 26)
        case .request: ("arrow.up.arrow.down", Theme.muted, 18)
        case .tool(let tool): (tool.success == false ? "xmark" : tool.decision == "reject" ? "hand.raised.fill" : "wrench.fill",
                               tool.success == false ? Theme.hot : tool.decision == "reject" ? Theme.warm : Theme.good, 20)
        case .error: ("exclamationmark", Theme.hot, 22)
        case .system: ("circle.fill", Theme.stroke, 10)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(offset)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 6)
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle().fill(Theme.stroke).frame(width: 2).frame(maxHeight: .infinity).padding(.top, 14)
                }
                Image(systemName: node.icon)
                    .font(.system(size: node.size * 0.42, weight: .bold))
                    .foregroundStyle(node.tint)
                    .frame(width: node.size, height: node.size)
                    .background(Circle().fill(Theme.panel))
                    .overlay(Circle().strokeBorder(node.tint.opacity(0.6), lineWidth: 1.5))
                    .padding(.top, node.size < 22 ? 4 : 0)
            }
            .frame(width: 26)
            TranscriptRow(item: item)
                .padding(.bottom, 12)
        }
    }
}

/// The content of a timeline step, drawn according to what kind of event it is.
struct TranscriptRow: View {
    var item: TranscriptItem
    @State private var expanded = false

    var body: some View {
        switch item.kind {
        case .prompt(let text, let length):
            bubble(title: "You", tint: Theme.accent, text: text,
                   missing: "Prompt text not captured\(length.map { " (\($0) characters)" } ?? ""). Launch Claude Code with bin/claude-otel to record it.")
        case .response(let text, let model, let length):
            bubble(title: "Claude" + (model.map { " · \(Format.modelName($0))" } ?? ""), tint: Theme.good, text: text,
                   missing: "Reply not captured\(length.map { " (\($0) characters)" } ?? "").")
        case .request(let model, let usage, let duration, let ttft):
            HStack(spacing: 8) {
                ModelChip(model: model)
                tokenChip("\(Format.tokens(usage.input)) in")
                tokenChip("\(Format.tokens(usage.output)) out")
                tokenChip("\(Format.tokens(usage.cacheRead)) cached")
                if let duration { tokenChip(Format.duration(ms: duration) + (ttft.map { " · first token \(Format.duration(ms: $0))" } ?? "")) }
                Spacer(minLength: 6)
                Text(Format.usd(usage.usd)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.warm)
            }
            .padding(.top, 2)
        case .tool(let tool):
            toolRow(tool)
        case .error(let message, let model, let status):
            Label("\(status.map { "HTTP \($0) · " } ?? "")\(message)\(model.map { " · \(Format.modelName($0))" } ?? "")",
                  systemImage: "exclamationmark.octagon.fill")
                .font(.system(size: 13)).foregroundStyle(Theme.hot)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.hot.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .system(let name, let detail):
            Text("\(name)\(detail.isEmpty ? "" : " · \(detail)")")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                .padding(.top, 1)
        }
    }

    private func tokenChip(_ text: String) -> some View {
        Text(text).font(.system(size: 11, design: .monospaced)).monospacedDigit()
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Theme.stroke.opacity(0.45), in: Capsule())
    }

    private var redactedLength: Int? {
        switch item.kind {
        case .prompt(_, let length), .response(_, _, let length): length
        default: nil
        }
    }

    private func bubble(title: String, tint: Color, text: String?, missing: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(tint)
            if text == redactedValue {
                Label("Redacted by policy at the relay\(redactedLength.map { " · \($0) characters" } ?? "")", systemImage: "lock.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.warm)
            } else if let text {
                Text(markdown(text)).font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.text).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(missing).font(.system(size: 13)).italic().foregroundStyle(Theme.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [tint.opacity(0.13), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(tint.opacity(0.28)))
    }

    private func toolRow(_ tool: TranscriptItem.Tool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { if tool.input != nil { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } } label: {
                HStack(spacing: 10) {
                    ToolIcon(name: tool.name)
                    Text(tool.name).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                    if tool.inputRedacted {
                        Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.warm)
                    }
                    Text(tool.summary).font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(tool.inputRedacted ? Theme.warm : Theme.body)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 8)
                    status(tool)
                    if tool.input != nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.muted)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded, let input = tool.input {
                Text(Transcript.prettyJSON(input))
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.body).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(Theme.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke.opacity(0.8)))
    }

    @ViewBuilder private func status(_ tool: TranscriptItem.Tool) -> some View {
        if tool.decision == "reject" {
            pill("rejected\(tool.decisionSource.map { " · \($0.replacingOccurrences(of: "_", with: " "))" } ?? "")", Theme.warm)
        } else if tool.success == false {
            pill("failed\(tool.durationMs.map { " · \(Format.duration(ms: $0))" } ?? "")", Theme.hot)
        } else if tool.success == true {
            pill("ok\(tool.durationMs.map { " · \(Format.duration(ms: $0))" } ?? "")", Theme.good)
        } else {
            pill("no result", Theme.muted)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 11, weight: .semibold)).monospacedDigit()
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(color).background(color.opacity(0.15), in: Capsule())
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

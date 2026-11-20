import Charts
import SwiftUI

struct ContentView: View {
    @Bindable var store: TelemetryStore

    enum Page: String, CaseIterable, Identifiable {
        case live = "Live", session = "Session"
        var id: String { rawValue }
    }

    /// Remembered between launches.
    @AppStorage("page") private var page: Page = .live
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SessionList(store: store) { page = .session }
                .navigationSplitViewColumnWidth(min: 290, ideal: 320, max: 380)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let error = store.error { ErrorBanner(message: error) }
                    switch page {
                    case .live: livePage
                    case .session:
                        if let session = store.selectedSession {
                            SessionDetail(session: session, models: store.models, commits: store.commits,
                                          transcript: store.transcript, backstage: store.backstage,
                                          insights: store.insights, insightsRunning: store.insightsRunning.contains(session.sessionID),
                                          insightsError: store.insightsError) { Task { await store.generateInsights() } }
                        } else {
                            ContentUnavailableView("Pick a session", systemImage: "sidebar.left",
                                                   description: Text("Choose one from the list to see its transcript."))
                                .padding(.top, 80)
                        }
                    }
                }
                .padding(28)
            }
            .background(
                ZStack {
                    Theme.background
                    RadialGradient(colors: [Theme.accentDeep.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 700)
                }
                .ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    // MARK: Header

    private var subtitle: String {
        switch page {
        case .live: "Tokens your agents are burning on this machine, read from your local ClickHouse"
        case .session: "Every prompt, reply, model call and tool call, what ran behind the scenes, and what to change"
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text(page == .live ? "Live burn" : "Session")
                    .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 13)).foregroundStyle(Theme.body)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                PillTabs(options: Page.allCases.map { ($0, $0.rawValue) }, selection: $page)
                LiveIndicator(updated: store.lastUpdated, failing: store.error != nil)
            }
        }
    }

    // MARK: Live page

    private var livePage: some View {
        VStack(alignment: .leading, spacing: 18) {
            statTiles
            HStack(alignment: .top, spacing: 18) {
                gaugePanel.frame(width: 410)
                minuteChart
            }
        }
    }

    private var statTiles: some View {
        let usage = store.totals.usage
        return HStack(spacing: 18) {
            StatTile(icon: "dollarsign", tint: Theme.warm, title: "Spend", value: Format.usd(usage.usd),
                     note: usage.unpriced > 0 ? "24 h · \(usage.unpriced) calls without a cost" : "24 h · every call priced")
            StatTile(icon: "circle.hexagongrid.fill", tint: Theme.accent, title: "Tokens", value: Format.tokens(usage.totalTokens),
                     note: "24 h · \(Format.percent(usage.cacheRead, of: usage.totalTokens)) cache reads")
            StatTile(icon: "bubble.left.and.text.bubble.right.fill", tint: Theme.good, title: "Sessions",
                     value: "\(store.totals.sessions)", note: "24 h · \(usage.calls) model calls")
            StatTile(icon: "text.cursor", tint: Theme.cacheRead, title: "Output", value: Format.tokens(usage.output),
                     note: "24 h · tokens generated")
        }
    }

    private var gaugePanel: some View {
        Panel(title: "Right now", icon: "gauge.with.dots.needle.67percent") {
            GaugeView(value: store.tokensPerMinute, maximum: store.gaugeMax)
                .frame(height: 300)
                .background(
                    RadialGradient(colors: [Theme.accentDeep.opacity(0.35 * min(1, store.tokensPerMinute / max(store.gaugeMax, 1)) + 0.08), .clear],
                                   center: .center, startRadius: 10, endRadius: 190))
            HStack {
                Label("Output \(Format.tokens(store.live.output)) tok/min", systemImage: "arrow.down.forward")
                Spacer()
                Label("\(store.live.calls) calls in 60 s", systemImage: "bolt.fill")
            }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.body)
            TokenMixBar(usage: store.live)
        }
    }

    private var minuteChart: some View {
        Panel(title: "Last 60 minutes", icon: "chart.bar.fill") {
            Chart(store.perMinute) { bucket in
                BarMark(x: .value("Minute", bucket.date, unit: .minute), y: .value("Tokens", bucket.tokens ?? 0))
                    .foregroundStyle(LinearGradient(colors: [Theme.accentDeep, Theme.accent, Theme.cacheRead],
                                                    startPoint: .bottom, endPoint: .top))
                    .cornerRadius(3)
            }
            .chartXScale(domain: Date.now.addingTimeInterval(-3600)...Date.now)
            .chartYAxis { AxisMarks { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 4])).foregroundStyle(Theme.stroke)
                AxisValueLabel { Text(Format.tokens(value.as(Double.self))).foregroundStyle(Theme.muted) }
            } }
            .chartXAxis { AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(Theme.muted)
            } }
            .frame(height: 392)
            .overlay { if store.perMinute.isEmpty { Text("No requests in the last hour").foregroundStyle(Theme.muted) } }
        }
    }
}

struct LiveIndicator: View {
    var updated: Date?
    var failing: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(failing ? Theme.hot : Theme.good).frame(width: 7, height: 7)
                .shadow(color: (failing ? Theme.hot : Theme.good).opacity(0.8), radius: pulse ? 5 : 1)
                .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                .onAppear { pulse = true }
            Text(failing ? "Disconnected" : updated.map { "Live · \($0.formatted(date: .omitted, time: .standard))" } ?? "Connecting…")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.muted)
        }
    }
}

struct StatTile: View {
    var icon: String
    var tint: Color
    var title: String
    var value: String
    var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tint)
                    .frame(width: 30, height: 30)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Spacer()
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2)
                    .foregroundStyle(Theme.muted)
            }
            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.body)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tint.opacity(0.10), Theme.panel], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

struct ErrorBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 13))
            .foregroundStyle(Theme.warm)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warm.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.warm.opacity(0.3)))
    }
}

// MARK: Sidebar

struct SessionList: View {
    @Bindable var store: TelemetryStore
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gauge.with.needle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(LinearGradient(colors: [Theme.accent, Theme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("AgentScope").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                    Text("localhost · ClickHouse").font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 16).padding(.top, 34).padding(.bottom, 18)

            HStack {
                Text("SESSIONS").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5)
                Spacer()
                Text("\(store.sessions.count)").font(.system(size: 10, weight: .semibold, design: .monospaced))
            }
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 16).padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.sessions) { session in
                        SessionRowView(session: session, selected: session.sessionID == store.selectedSessionID,
                                       maxSpend: store.maxSessionSpend)
                            .onTapGesture {
                                store.selectedSessionID = session.sessionID
                                onOpen()
                            }
                    }
                }
                .padding(.horizontal, 10).padding(.bottom, 16)
            }
            .overlay {
                if store.sessions.isEmpty {
                    ContentUnavailableView("No sessions yet", systemImage: "waveform.path.ecg",
                                           description: Text("Run bin/claude-otel, or scripts/seed.sh for demo data."))
                }
            }
        }
        .background(Theme.sidebar)
        .toolbar(removing: .sidebarToggle)
    }
}

struct SessionRowView: View {
    var session: SessionRow
    var selected: Bool
    var maxSpend: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(session.modelList.prefix(2), id: \.self) { ModelChip(model: $0) }
                Spacer()
                Text(Format.relative(session.lastSeenAt)).font(.system(size: 10)).foregroundStyle(Theme.muted)
            }
            Text(session.title ?? "Session \(Format.shortID(session.sessionID))")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(session.title == nil ? Theme.body : Theme.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                Text(Format.usd(session.usage.usd)).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                GeometryReader { proxy in
                    Capsule().fill(Theme.stroke)
                        .overlay(alignment: .leading) {
                            Capsule().fill(LinearGradient(colors: [Theme.accentDeep, Theme.accent], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(3, proxy.size.width * min(1, (session.usage.usd ?? 0) / max(maxSpend, 0.0001))))
                        }
                }
                .frame(height: 4)
                Text(Format.tokens(session.usage.totalTokens)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Theme.accentDeep.opacity(0.22) : Theme.panel.opacity(0.6)))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.accent.opacity(0.55) : Theme.stroke.opacity(0.6)))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

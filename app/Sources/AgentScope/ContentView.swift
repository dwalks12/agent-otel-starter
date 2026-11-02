import Charts
import SwiftUI

struct ContentView: View {
    @Bindable var store: TelemetryStore

    var body: some View {
        NavigationSplitView {
            SessionList(store: store)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if let error = store.error { ErrorBanner(message: error) }
                    statTiles
                    HStack(alignment: .top, spacing: 16) {
                        gaugePanel.frame(width: 400)
                        minuteChart
                    }
                    if let session = store.selectedSession {
                        SessionDetail(session: session, models: store.models, commits: store.commits)
                    }
                }
                .padding(24)
            }
            .background(Theme.background)
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live burn").font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Tokens your agents are burning on this machine, read from your local ClickHouse")
                    .foregroundStyle(Theme.body)
            }
            Spacer()
            if let updated = store.lastUpdated {
                Label("Updated \(updated.formatted(date: .omitted, time: .standard))", systemImage: "dot.radiowaves.left.and.right")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
    }

    private var gaugePanel: some View {
        Panel {
            GaugeView(value: store.tokensPerMinute, maximum: store.gaugeMax)
                .frame(height: 300)
            HStack {
                Text("Output \(Format.tokens(store.live.output)) tok/min")
                Spacer()
                Text("\(store.live.calls) calls in 60 s")
            }
            .font(.system(size: 13)).foregroundStyle(Theme.body)
            Text("MIX RIGHT NOW").font(.system(size: 11, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Theme.muted)
            TokenMixBar(usage: store.live)
        }
    }

    private var statTiles: some View {
        let usage = store.totals.usage
        return HStack(spacing: 16) {
            StatTile(title: "Spend · 24 h", value: Format.usd(usage.usd),
                     note: usage.unpriced > 0 ? "\(usage.unpriced) calls without a cost" : "every call priced")
            StatTile(title: "Tokens · 24 h", value: Format.tokens(usage.totalTokens),
                     note: "\(Format.percent(usage.cacheRead, of: usage.totalTokens)) cache reads")
            StatTile(title: "Sessions · 24 h", value: "\(store.totals.sessions)", note: "\(usage.calls) model calls")
            StatTile(title: "Output · 24 h", value: Format.tokens(usage.output), note: "tokens generated")
        }
    }

    private var minuteChart: some View {
        Panel(title: "Last 60 minutes") {
            Chart(store.perMinute) { bucket in
                BarMark(x: .value("Minute", bucket.date, unit: .minute), y: .value("Tokens", bucket.tokens ?? 0))
                    .foregroundStyle(Theme.accent.gradient)
            }
            .chartXScale(domain: Date.now.addingTimeInterval(-3600)...Date.now)
            .chartYAxis { AxisMarks { value in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel { Text(Format.tokens(value.as(Double.self))).foregroundStyle(Theme.muted) }
            } }
            .chartXAxis { AxisMarks(values: .stride(by: .minute, count: 15)) { _ in
                AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(Theme.muted)
            } }
            .frame(height: 382)
            .overlay { if store.perMinute.isEmpty { Text("No requests in the last hour").foregroundStyle(Theme.muted) } }
        }
    }
}

struct StatTile: View {
    var title: String
    var value: String
    var note: String

    var body: some View {
        Panel(title: title) {
            Text(value).font(.system(size: 30, weight: .semibold, design: .monospaced)).foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(note).font(.system(size: 12)).foregroundStyle(Theme.body)
        }
    }
}

struct ErrorBanner: View {
    var message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(Theme.warm)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.warm.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct SessionList: View {
    @Bindable var store: TelemetryStore

    var body: some View {
        List(selection: $store.selectedSessionID) {
            Section("Sessions") {
                ForEach(store.sessions) { session in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(Format.shortID(session.sessionID)).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(Format.usd(session.usage.usd)).monospacedDigit().foregroundStyle(Theme.text)
                        }
                        HStack {
                            Text(session.models).lineLimit(1)
                            Spacer()
                            Text(Format.relative(session.lastSeenAt))
                        }
                        .font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 4)
                    .tag(session.sessionID)
                }
            }
        }
        .overlay {
            if store.sessions.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "waveform.path.ecg",
                                       description: Text("Run bin/claude-otel, or scripts/seed.sh for demo data."))
            }
        }
    }
}

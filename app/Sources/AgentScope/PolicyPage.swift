import SwiftUI

/// Choose what the relay keeps or redacts, and see it working.
struct PolicyPage: View {
    @Bindable var store: TelemetryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            pipeline
            if let relay = store.relay {
                rules(relay)
                Label("Changes apply to telemetry from now on. What’s already stored isn’t rewritten; run scripts/reset-data.sh to start clean.",
                      systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            } else {
                Panel(title: "Relay offline", icon: "bolt.horizontal.circle") {
                    Text("Can’t reach the policy relay on localhost:4318. Start the stack with ./run.sh.")
                        .font(.system(size: 13)).foregroundStyle(Theme.body)
                    if let error = store.relayError {
                        Text(error).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
    }

    // MARK: Pipeline

    private var pipeline: some View {
        Panel(title: "Where your telemetry goes", icon: "point.3.connected.trianglepath.dotted") {
            HStack(spacing: 0) {
                node("Claude Code", "bin/claude-otel", icon: "terminal.fill", tint: Theme.body)
                arrow
                relayNode
                arrow
                node("Collector", "OTLP → ClickHouse", icon: "arrow.triangle.merge", tint: Theme.body)
                arrow
                node("ClickHouse", "otel.otel_logs", icon: "cylinder.split.1x2.fill", tint: Theme.body)
            }
        }
    }

    private var relayNode: some View {
        let relay = store.relay
        let redacted = relay?.stats.redacted.values.reduce(0, +) ?? 0
        let active = PolicyRule.all.filter { relay?.redacts($0) == true }.count
        return VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.accentDeep.opacity(relay == nil ? 0.15 : 0.45)).frame(width: 52, height: 52)
                Image(systemName: relay == nil ? "shield.slash.fill" : "checkmark.shield.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(relay == nil ? Theme.hot : Theme.accent)
            }
            Text("Policy relay").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Text(relay == nil ? "offline" : active == 0 ? "keeping everything" : "redacting \(active) of \(PolicyRule.all.count)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(relay == nil ? Theme.hot : Theme.accent)
            if let stats = relay?.stats {
                Text("\(stats.records) records · \(redacted) fields redacted")
                    .font(.system(size: 11, design: .monospaced)).monospacedDigit().foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.accentDeep.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.accent.opacity(relay == nil ? 0.15 : 0.45)))
    }

    private func node(_ title: String, _ detail: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.stroke.opacity(0.6)).frame(width: 44, height: 44)
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(tint)
            }
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Text(detail).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private var arrow: some View {
        Image(systemName: "chevron.right.2").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted.opacity(0.7))
            .frame(width: 28)
    }

    // MARK: Rules

    private func rules(_ relay: RelayState) -> some View {
        Panel(title: "Policy", icon: "lock.shield") {
            VStack(spacing: 0) {
                ForEach(Array(PolicyRule.all.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { Divider().overlay(Theme.stroke) }
                    row(rule, relay: relay)
                }
            }
        }
    }

    private func row(_ rule: PolicyRule, relay: RelayState) -> some View {
        let redacting = relay.redacts(rule)
        let count = relay.stats.redacted[rule.id] ?? 0
        return HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill((redacting ? Theme.warm : Theme.good).opacity(0.16)).frame(width: 36, height: 36)
                Image(systemName: rule.icon).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(redacting ? Theme.warm : Theme.good)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(rule.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text(rule.detail).font(.system(size: 12)).foregroundStyle(Theme.body)
            }
            Spacer(minLength: 12)
            if count > 0 {
                Text("\(count) redacted").font(.system(size: 11, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(Theme.muted).contentTransition(.numericText())
            }
            PillTabs(options: [(false, "Keep"), (true, "Redact")], selection: Binding(
                get: { redacting },
                set: { redact in Task { await store.setPolicy(rule, redact: redact) } }))
        }
        .padding(.vertical, 12)
        .animation(.snappy(duration: 0.25), value: redacting)
    }
}

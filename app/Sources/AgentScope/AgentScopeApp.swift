import AppKit
import SwiftUI

@main
struct AgentScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = TelemetryStore(
        client: ClickHouseClient(baseURL: URL(string: env("AGENT_OTEL_CLICKHOUSE_URL") ?? "http://localhost:8123")!),
        relay: RelayClient(baseURL: URL(string: env("AGENT_OTEL_RELAY_URL") ?? "http://localhost:4318")!))

    var body: some Scene {
        WindowGroup("AgentScope") {
            ContentView(store: store)
                .frame(minWidth: 1100, minHeight: 720)
                .task { await store.run() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private func env(_ name: String) -> String? { ProcessInfo.processInfo.environment[name] }

/// `swift run` starts a bare executable; this makes it a regular foreground app with a Dock icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

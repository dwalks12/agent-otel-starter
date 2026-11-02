// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AgentScope",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "AgentScope", path: "Sources/AgentScope")
    ]
)

// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LeafSend",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "LeafSendCore"),
        .executableTarget(name: "LeafSend", dependencies: ["LeafSendCore"]),
        // Assert-based self-check: `swift run LeafSendCheck` (no XCTest needed with Command Line Tools).
        .executableTarget(name: "LeafSendCheck", dependencies: ["LeafSendCore"]),
    ]
)

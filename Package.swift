// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WorkDock",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    targets: [
        .systemLibrary(
            name: "Clibxml2",
            path: "Sources/Clibxml2"
        ),
        .target(
            name: "XMLBridge",
            dependencies: ["Clibxml2"],
            path: "Sources/XMLBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "WorkDock",
            dependencies: ["XMLBridge"],
            path: "Sources/WorkDock",
            resources: [.process("Resources")]
        ),
    ]
)

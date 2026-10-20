// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "thumbs-out",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure detection + policy logic. No system calls, fully unit-tested.
        .target(name: "ThumbsOutCore"),
        // Menu bar app: process listing (libproc), sleep assertions (IOKit), SwiftUI UI.
        .executableTarget(
            name: "ThumbsOut",
            dependencies: ["ThumbsOutCore"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        ),
        .testTarget(name: "ThumbsOutCoreTests", dependencies: ["ThumbsOutCore"]),
    ]
)

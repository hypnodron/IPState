// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPState",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IPStateCore", targets: ["IPStateCore"]),
        .executable(name: "IPState", targets: ["IPState"])
    ],
    targets: [
        .target(name: "IPStateCore"),
        .executableTarget(name: "IPState", dependencies: ["IPStateCore"]),
        .target(name: "IPStateTestSupport", path: "Tests/IPStateTestSupport"),
        .testTarget(name: "IPStateCoreTests", dependencies: ["IPStateCore", "IPStateTestSupport"]),
        .testTarget(name: "IPStateTests", dependencies: ["IPState", "IPStateCore", "IPStateTestSupport"])
    ]
)

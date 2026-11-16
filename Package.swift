// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IPState",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "IPStateCore", targets: ["IPStateCore"]),
        .executable(name: "IPState", targets: ["IPState"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .target(name: "IPStateCore"),
        .executableTarget(name: "IPState", dependencies: [
            "IPStateCore", .product(name: "Sparkle", package: "Sparkle")
        ], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .target(name: "IPStateTestSupport", path: "Tests/IPStateTestSupport"),
        .testTarget(name: "IPStateCoreTests", dependencies: ["IPStateCore", "IPStateTestSupport"]),
        .testTarget(name: "IPStateTests", dependencies: ["IPState", "IPStateCore", "IPStateTestSupport"])
    ]
)

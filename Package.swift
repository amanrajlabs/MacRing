// swift-tools-version:6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "MacRing",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MacRingKit",
            path: "Sources/MacRingKit",
            swiftSettings: v5
        ),
        .executableTarget(
            name: "MacRing",
            dependencies: ["MacRingKit"],
            path: "Sources/MacRing",
            swiftSettings: v5
        ),
        // CLT-only environments lack XCTest/Testing, so checks are a plain
        // executable: `swift run MacRingChecks`.
        .executableTarget(
            name: "MacRingChecks",
            dependencies: ["MacRingKit"],
            path: "Sources/MacRingChecks",
            swiftSettings: v5
        ),
    ]
)

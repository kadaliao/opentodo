// swift-tools-version: 6.2
import PackageDescription

/// Approachable concurrency for every target; the UI target also defaults to
/// the main actor (Swift 6.2's `defaultIsolation`), the others stay
/// nonisolated so they can run off the main thread.
let concurrency: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "OpenTodoKit",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "OpenTodoDomain", targets: ["OpenTodoDomain"]),
        .library(name: "OpenTodoData", targets: ["OpenTodoData"]),
        .library(name: "OpenTodoUI", targets: ["OpenTodoUI"]),
        // What the app's extensions (widgets, share) and intents share with
        // the app: links, widget contents, writes from outside the app.
        .library(name: "OpenTodoSystem", targets: ["OpenTodoSystem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
    ],
    targets: [
        .target(name: "OpenTodoDomain", swiftSettings: concurrency),
        .target(
            name: "OpenTodoData",
            dependencies: ["OpenTodoDomain", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: concurrency
        ),
        .target(
            name: "OpenTodoSystem",
            dependencies: ["OpenTodoDomain", "OpenTodoData", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: concurrency
        ),
        .target(
            name: "OpenTodoUI",
            dependencies: ["OpenTodoDomain", "OpenTodoData", "OpenTodoSystem"],
            swiftSettings: concurrency + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "OpenTodoDomainTests", dependencies: ["OpenTodoDomain"], swiftSettings: concurrency),
        .testTarget(name: "OpenTodoDataTests", dependencies: ["OpenTodoData"], swiftSettings: concurrency),
        .testTarget(name: "OpenTodoSystemTests", dependencies: ["OpenTodoSystem"], swiftSettings: concurrency),
        .testTarget(
            name: "OpenTodoUITests",
            dependencies: ["OpenTodoUI"],
            swiftSettings: concurrency + [.defaultIsolation(MainActor.self)]
        ),
    ],
    swiftLanguageModes: [.v6]
)

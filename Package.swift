// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "Nark",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Recording", targets: ["Recording"]),
        .library(name: "NarkUI", targets: ["NarkUI"]),
        .library(name: "NarkApplication", targets: ["NarkApplication"]),
        .library(name: "NarkExtension", targets: ["NarkExtension"]),
        .library(name: "Firewall", targets: ["Firewall"]),
        .library(name: "Vocabulary", targets: ["Vocabulary"]),
        .library(name: "Control", targets: ["Control"]),
        .library(name: "Monitor", targets: ["Monitor"]),
        .executable(name: "nark", targets: ["nark"]),
        .executable(name: "NarkFilter", targets: ["NarkFilter"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-composable-architecture",
            exact: "1.26.2"
        ),
        .package(
            url: "https://github.com/ollieatkinson/Lexicon",
            revision: "104ed130265074ac701464f72e266ef326c59f8a"
        ),
        .package(url: "https://github.com/apple/swift-argument-parser", exact: "1.8.2"),
        .package(url: "https://github.com/pointfreeco/swift-issue-reporting", exact: "2.1.2"),
        .package(url: "https://github.com/SwiftTUI/swift-tui", exact: "0.19.3"),
    ],
    targets: [
        .target(name: "Geography", resources: [.process("Resources")]),
        .target(name: "Firewall", dependencies: ["Vocabulary"]),
        .target(
            name: "Vocabulary",
            dependencies: [.product(name: "SwiftLexicon", package: "Lexicon")],
            exclude: ["nark.lexicon"],
            plugins: [.plugin(name: "SwiftLibraryGeneratorPlugin", package: "Lexicon")]
        ),
        .target(name: "Control", dependencies: ["Firewall", "Vocabulary"]),
        .target(
            name: "Monitor",
            dependencies: [
                "Firewall",
                "Control",
                "Vocabulary",
                "Geography",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ]
        ),
        .target(name: "Recording", dependencies: ["Firewall"]),
        .target(
            name: "NarkUI",
            dependencies: [
                "Vocabulary",
                "Firewall",
                "Geography",
                .product(name: "SwiftTUI", package: "swift-tui")
            ]
        ),
        .target(
            name: "NarkApplication",
            dependencies: [
                "Firewall",
                "Monitor",
                "Control",
                "Vocabulary",
                "NarkUI",
                "Recording",
                "Geography",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "SwiftTUI", package: "swift-tui"),
                .product(name: "SwiftTUIRuntime", package: "swift-tui"),
                .product(name: "SwiftTUICLI", package: "swift-tui"),
            ]
        ),
        .target(name: "NarkExtension", dependencies: ["Firewall", "Control", "Vocabulary"]),
        .executableTarget(name: "nark", dependencies: ["NarkApplication"], path: "App/Nark"),
        .executableTarget(
            name: "NarkFilter",
            dependencies: ["NarkExtension"],
            path: "App/NarkFilter"
        ),
        .target(name: "TestSupport", dependencies: ["Control", "Firewall"], path: "Tests/Support"),
        .testTarget(
            name: "NarkApplicationTests",
            dependencies: [
                "NarkApplication",
                "NarkUI",
                "Monitor",
                "Firewall",
                "Control",
                "Vocabulary",
                "Geography",
                "TestSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "IssueReportingTestSupport", package: "swift-issue-reporting"),
                .product(name: "SwiftTUICLI", package: "swift-tui"),
                .product(name: "SwiftTUI", package: "swift-tui")
            ]
        ),
        .testTarget(name: "GeographyTests", dependencies: ["Geography"]),
        .testTarget(name: "RecordingTests", dependencies: ["Recording", "Firewall"]),
        .testTarget(
            name: "FirewallTests",
            dependencies: ["Firewall"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(
            name: "MonitorTests",
            dependencies: [
                "Monitor",
                "TestSupport",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
                .product(name: "IssueReportingTestSupport", package: "swift-issue-reporting"),
            ]
        ),
        .testTarget(
            name: "ControlTests",
            dependencies: [
                "Control",
                "Vocabulary",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

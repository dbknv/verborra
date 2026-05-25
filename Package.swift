// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Verborra",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown", from: "0.4.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "Verborra",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Atomics", package: "swift-atomics"),
            ],
            path: "Verborra"
        ),
        .testTarget(
            name: "VerborraTests",
            dependencies: ["Verborra"],
            path: "VerborraTests"
        ),
    ]
)

// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "taskmatter",
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
        .package(
            url: "https://github.com/woodymelling/swift-frontmatter-parsing",
            revision: "b8b635afe8e0b94f75fe3083ea0238da418ca8e8"),
        .package(
            url: "https://github.com/jpsim/Yams",
            from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "taskmatter",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "FrontmatterParsing", package: "swift-frontmatter-parsing"),
                .product(name: "Yams", package: "yams"),
            ],
            path: "Sources")
    ]
)

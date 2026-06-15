// swift-tools-version:5.10
// Package.swift exists alongside project.yml so that `swift build` and
// `swift test` can compile-check the Swift sources without requiring a full
// Xcode installation. The shipped product is the Xcode-generated .app bundle;
// this manifest is for CI/local syntax checking and unit tests only.
import PackageDescription

let package = Package(
    name: "MacZoomer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MacZoomerCore", targets: ["MacZoomerCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")
    ],
    targets: [
        .target(
            name: "MacZoomerCore",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/MacZoomer",
            exclude: [
                "Resources/Info.plist",
                "Resources/MacZoomer.entitlements"
            ]
        ),
        .testTarget(
            name: "MacZoomerTests",
            dependencies: ["MacZoomerCore"],
            path: "Tests/MacZoomerTests"
        )
    ]
)

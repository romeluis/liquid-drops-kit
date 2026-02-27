// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidDropsKit",
    platforms: [
        .iOS("26.0")
    ],
    products: [
        .library(
            name: "LiquidDropsKit",
            targets: ["LiquidDropsKit"]
        )
    ],
    targets: [
        .target(
            name: "LiquidDropsKit"
        ),
        .testTarget(
            name: "LiquidDropsKitTests",
            dependencies: ["LiquidDropsKit"]
        )
    ],
    swiftLanguageModes: [
        .v5
    ]
)

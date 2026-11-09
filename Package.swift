// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sublevel",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Sublevel", targets: ["Sublevel"])
    ],
    targets: [
        .executableTarget(
            name: "Sublevel",
            path: "Sources/Sublevel",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Network"),
                .linkedFramework("GameController")
            ]
        ),
        .testTarget(
            name: "SublevelTests",
            dependencies: ["Sublevel"],
            path: "Tests/SublevelTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

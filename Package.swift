// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TypeSteady",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "TypeSteady", targets: ["TypeSteadyApp"])
    ],
    targets: [
        .executableTarget(
            name: "TypeSteadyApp",
            path: "Sources/TypeSteadyApp",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "TypeSteadyAppTests",
            dependencies: ["TypeSteadyApp"],
            path: "Tests/TypeSteadyAppTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

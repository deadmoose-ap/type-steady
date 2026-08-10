// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LangSwitcher",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "LangSwitcher", targets: ["LangSwitcherApp"])
    ],
    targets: [
        .executableTarget(
            name: "LangSwitcherApp",
            path: "Sources/LangSwitcherApp",
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
            name: "LangSwitcherAppTests",
            dependencies: ["LangSwitcherApp"],
            path: "Tests/LangSwitcherAppTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

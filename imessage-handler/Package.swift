// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "imessage-handler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "iMessageHandlerCore", targets: ["iMessageHandlerCore"]),
        .executable(name: "imessage-handler", targets: ["iMessageHandlerCLI"]),
        .executable(name: "IMessageHandlerMenuBar", targets: ["iMessageHandlerMenuBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftpackages/DotEnv.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "iMessageHandlerCore",
            dependencies: [
                .product(name: "DotEnv", package: "DotEnv")
            ],
            linkerSettings: [
                .linkedFramework("Contacts"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "iMessageHandlerCLI",
            dependencies: ["iMessageHandlerCore"]
        ),
        .executableTarget(
            name: "iMessageHandlerMenuBar",
            dependencies: ["iMessageHandlerCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "iMessageHandlerTests",
            dependencies: ["iMessageHandlerCore"]
        )
    ]
)

// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "imessage-handler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "imessage-handler", targets: ["iMessageHandler"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftpackages/DotEnv.git", from: "3.0.0")
    ],
    targets: [
        .executableTarget(
            name: "iMessageHandler",
            dependencies: [
                .product(name: "DotEnv", package: "DotEnv")
            ],
            linkerSettings: [
                .linkedFramework("Contacts"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "iMessageHandlerTests",
            dependencies: ["iMessageHandler"]
        )
    ]
)

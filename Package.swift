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
    targets: [
        .executableTarget(
            name: "iMessageHandler",
            linkerSettings: [
                .linkedFramework("Contacts"),
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)

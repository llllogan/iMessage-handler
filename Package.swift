// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "apple-handler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CalendarHandlerCore", targets: ["CalendarHandlerCore"]),
        .library(name: "iMessageHandlerCore", targets: ["iMessageHandlerCore"]),
        .executable(name: "calendar-handler", targets: ["CalendarHandlerCLI"]),
        .executable(name: "imessage-handler", targets: ["iMessageHandlerCLI"]),
        .executable(name: "CalendarHandlerMenuBar", targets: ["CalendarHandlerMenuBar"]),
        .executable(name: "IMessageHandlerMenuBar", targets: ["iMessageHandlerMenuBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftpackages/DotEnv.git", from: "3.0.0")
    ],
    targets: [
        .target(
            name: "CalendarHandlerCore",
            path: "calendar-handler/Sources/CalendarHandlerCore",
            linkerSettings: [
                .linkedFramework("EventKit")
            ]
        ),
        .executableTarget(
            name: "CalendarHandlerCLI",
            dependencies: ["CalendarHandlerCore"],
            path: "calendar-handler/Sources/CalendarHandlerCLI"
        ),
        .executableTarget(
            name: "CalendarHandlerMenuBar",
            dependencies: ["CalendarHandlerCore"],
            path: "calendar-handler/Sources/CalendarHandlerMenuBar",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .target(
            name: "iMessageHandlerCore",
            dependencies: [
                .product(name: "DotEnv", package: "DotEnv")
            ],
            path: "imessage-handler/Sources/iMessageHandlerCore",
            linkerSettings: [
                .linkedFramework("Contacts"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "iMessageHandlerCLI",
            dependencies: ["iMessageHandlerCore"],
            path: "imessage-handler/Sources/iMessageHandlerCLI"
        ),
        .executableTarget(
            name: "iMessageHandlerMenuBar",
            dependencies: ["iMessageHandlerCore"],
            path: "imessage-handler/Sources/iMessageHandlerMenuBar",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "CalendarHandlerTests",
            dependencies: ["CalendarHandlerCore"],
            path: "calendar-handler/Tests/CalendarHandlerTests"
        ),
        .testTarget(
            name: "iMessageHandlerTests",
            dependencies: ["iMessageHandlerCore"],
            path: "imessage-handler/Tests/iMessageHandlerTests"
        )
    ]
)

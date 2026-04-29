// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "calendar-handler",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CalendarHandlerCore", targets: ["CalendarHandlerCore"]),
        .executable(name: "calendar-handler", targets: ["CalendarHandlerCLI"]),
        .executable(name: "CalendarHandlerMenuBar", targets: ["CalendarHandlerMenuBar"])
    ],
    targets: [
        .target(
            name: "CalendarHandlerCore",
            linkerSettings: [
                .linkedFramework("EventKit")
            ]
        ),
        .executableTarget(
            name: "CalendarHandlerCLI",
            dependencies: ["CalendarHandlerCore"]
        ),
        .executableTarget(
            name: "CalendarHandlerMenuBar",
            dependencies: ["CalendarHandlerCore"],
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        ),
        .testTarget(
            name: "CalendarHandlerTests",
            dependencies: ["CalendarHandlerCore"]
        )
    ]
)

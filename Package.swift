// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CritMonitor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CritMonitor", targets: ["CritMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "CritMonitor",
            path: "Sources/CritMonitor",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Charts"),
                .linkedFramework("IOKit"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "CritMonitorTests",
            dependencies: ["CritMonitor"],
            path: "Tests/CritMonitorTests"
        )
    ]
)

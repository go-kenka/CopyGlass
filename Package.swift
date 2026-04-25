// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CopyGlass",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CopyGlass", targets: ["CopyGlass"])
    ],
    dependencies: [
        // Add dependencies here later if needed, e.g., for HotKey
    ],
    targets: [
        .executableTarget(
            name: "CopyGlass",
            path: "Sources",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .testTarget(
            name: "CopyGlassTests",
            dependencies: ["CopyGlass"]
        )
    ]
)

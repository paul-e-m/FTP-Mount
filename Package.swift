// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FTPMount",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FTPMount", targets: ["FTPMount"])
    ],
    targets: [
        .executableTarget(
            name: "FTPMount",
            path: "Sources/FTPMount",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)

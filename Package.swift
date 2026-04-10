// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RetinaAware",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "retina-aware", targets: ["RetinaAware"]),
    ],
    targets: [
        .executableTarget(
            name: "RetinaAware",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-framework", "-Xlinker", "DisplayServices", "-Xlinker", "-F", "-Xlinker", "/System/Library/PrivateFrameworks"])
            ]
        ),
    ]
)

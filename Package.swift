// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RetinaAware",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "retina-aware", targets: ["RetinaAware"]),
    ],
    dependencies: [
        // We can add dependencies here if needed, but we'll stick to native APIs for now
    ],
    targets: [
        .executableTarget(
            name: "RetinaAware",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-framework", "-Xlinker", "DisplayServices",
                    "-Xlinker", "-framework", "-Xlinker", "ServiceManagement",
                    "-Xlinker", "-F", "-Xlinker", "/System/Library/PrivateFrameworks"
                ])
            ]
        ),
    ]
)

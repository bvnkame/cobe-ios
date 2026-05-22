// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "Cobe",
    platforms: [.iOS(.v13), .macOS(.v11)],
    products: [
        .library(name: "Cobe", targets: ["Cobe"]),
    ],
    targets: [
        .target(
            name: "Cobe",
            resources: [
                .process("Resources"),
                .process("Shaders.metal"),
            ]
        ),
    ]
)

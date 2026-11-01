// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Luma",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Luma", targets: ["Luma"])
    ],
    targets: [
        .executableTarget(name: "Luma")
    ]
)

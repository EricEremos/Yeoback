// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Cleanup",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Cleanup", targets: ["Cleanup"])],
    targets: [.executableTarget(name: "Cleanup", path: "Sources/Cleanup")]
)

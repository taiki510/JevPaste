// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JevPaste",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JevPaste", targets: ["JevPaste"]),
    ],
    targets: [
        .executableTarget(name: "JevPaste"),
        .testTarget(name: "JevPasteTests", dependencies: ["JevPaste"]),
    ]
)

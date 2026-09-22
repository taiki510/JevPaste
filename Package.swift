// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "JevPaste",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JevPaste", targets: ["JevPaste"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "6.3.2"),
    ],
    targets: [
        .executableTarget(name: "JevPaste"),
        .testTarget(
            name: "JevPasteTests",
            dependencies: [
                "JevPaste",
                .product(name: "Testing", package: "swift-testing"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)

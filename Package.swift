// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDSC",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/ConnorGibbons/RTLSDRWrapper", from: "1.0.2"),
        .package(url: "https://github.com/ConnorGibbons/SignalTools", from: "1.1.1"),
        .package(url: "https://github.com/ConnorGibbons/TCPUtils", from: "1.0.4"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftDSC",
            dependencies: [
                .product(name: "RTLSDRWrapper", package: "RTLSDRWrapper"),
                .product(name: "SignalTools", package: "SignalTools"),
                .product(name: "TCPUtils", package: "TCPUtils"),
            ]
        ),
        .testTarget(
            name: "SwiftDSCTests",
            dependencies: ["SwiftDSC"],
            resources: [
                .process("TestData")
            ]
        ),
    ]
)

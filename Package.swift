// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDSC",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/ConnorGibbons/RTLSDRWrapper", revision: "9dd86782273d5a8dcd48afb7cc41c85a897b6d7a"),
        .package(url: "https://github.com/ConnorGibbons/SignalTools", revision: "70c15c5e659b009fb2c3276e6a72b1e31295ea1e"),
        .package(url: "https://github.com/ConnorGibbons/TCPUtils", from: "1.0.3"),
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

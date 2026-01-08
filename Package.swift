// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDSC",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/ConnorGibbons/SignalTools", from: "1.1.3"),
        .package(url: "https://github.com/ConnorGibbons/TCPUtils", from: "1.0.4"),
        .package(url: "https://github.com/ConnorGibbons/SoapySDRWrapper", revision: "6a02bf5fa0dbaf9eb533525f5338167e9b9da20f")
    ],
    targets: [
        .executableTarget(
            name: "SwiftDSC",
            dependencies: [
                .product(name: "SignalTools", package: "SignalTools"),
                .product(name: "TCPUtils", package: "TCPUtils"),
                .product(name: "SoapySDRWrapper", package: "SoapySDRWrapper")
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

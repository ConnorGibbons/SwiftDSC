// swift-tools-version:5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftDSC",
    platforms: [
        .macOS(.v10_15),
    ],
    dependencies: [
        .package(url: "https://github.com/ConnorGibbons/SignalTools", branch: "main"),
        .package(url: "https://github.com/ConnorGibbons/Networking", branch: "main"),
        .package(url: "https://github.com/ConnorGibbons/SoapySDRWrapper", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "SwiftDSC",
            dependencies: [
                .product(name: "SignalTools", package: "SignalTools"),
                .product(name: "Networking", package: "Networking"),
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

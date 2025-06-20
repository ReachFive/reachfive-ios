// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Reach5",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "Reach5", targets: ["Reach5"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", .upToNextMajor(from: "5.9.1")),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift.git", .upToNextMajor(from: "1.8.2")),
        .package(url    : "https://github.com/devicekit/DeviceKit.git", .upToNextMajor(from: "5.1.0")),
    ],
    targets: [
        .target(
            name: "Reach5",
            dependencies: [
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "DeviceKit", package: "DeviceKit"),
            ],
            resources: [.copy("Core/PrivacyInfo.xcprivacy")]
        )
    ]
)

// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Reach5",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "Reach5", targets: ["Reach5"]),
    ],
    targets: [
        .target(
            name: "Reach5",
            resources: [.copy("Core/PrivacyInfo.xcprivacy")]
        )
    ]
)

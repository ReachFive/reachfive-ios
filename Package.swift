// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "Reach5",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "Reach5", targets: ["Reach5"]),
    ],
    targets: [
        .target(
            name: "Reach5",
            path: "Sources/Core",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .testTarget(
            name: "Reach5Tests",
            dependencies: ["Reach5"],
            path: "Tests/Reach5Tests"
        )
    ]
)

// Opt-in, compile-only target that type-checks the documentation code examples
// against the public API. Enabled only when DOC_EXAMPLES is set, so it never
// ships with the SDK. See docs/verification/.
if ProcessInfo.processInfo.environment["DOC_EXAMPLES"] != nil {
    package.products.append(.library(name: "DocExamples", targets: ["DocExamples"]))
    package.targets.append(
        .target(
            name: "DocExamples",
            dependencies: ["Reach5"],
            path: "docs/verification/Sources"
        )
    )
}

// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription
import Foundation

let package = Package(
    name: "Reach5",
    // macOS is declared for the macro plugin only: swift-syntax needs 10.15 on the build machine. The SDK
    // itself is still iOS-only — nothing in `Reach5` is available on macOS beyond Mac Catalyst, which is
    // iOS-flavoured and needs no declaration here.
    platforms: [.iOS(.v13), .macOS(.v10_15)],
    products: [
        .library(name: "Reach5", targets: ["Reach5"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
    ],
    targets: [
        .target(
            name: "Reach5",
            dependencies: ["Reach5URLValidation", "Reach5Macros"],
            path: "Sources/Core",
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        // The URL rules the macro plugin and the SDK share. Pure Foundation on purpose: the plugin is a
        // macOS executable, so anything reachable from here has to build for the build machine too.
        .target(
            name: "Reach5URLValidation",
            path: "Sources/Reach5URLValidation"
        ),
        .macro(
            name: "Reach5Macros",
            dependencies: [
                "Reach5URLValidation",
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            ],
            path: "Sources/Reach5Macros"
        ),
        .testTarget(
            name: "Reach5Tests",
            dependencies: ["Reach5"],
            path: "Tests/Reach5Tests"
        ),
    ]
)

// The macro's own tests, opt-in behind MACRO_TESTS because they cannot share a destination with the rest of
// the suite: `Reach5Macros` is an executable built for the build machine, so a test target that imports it
// only builds for macOS, while `Reach5Tests` needs iOS or Mac Catalyst for UIKit. Declaring both at once
// leaves whichever destination is chosen with a target it cannot build.
//
// With MACRO_TESTS set, the SDK targets are dropped rather than merely skipped: `swift test` builds every
// target in the graph before filtering, and `Reach5` does not build for macOS.
//
//     MACRO_TESTS=1 swift test                                                        # the macro
//     xcodebuild -scheme Reach5 -destination 'platform=macOS,variant=Mac Catalyst' test  # everything else
if ProcessInfo.processInfo.environment["MACRO_TESTS"] != nil {
    package.targets.removeAll { $0.name == "Reach5" || $0.name == "Reach5Tests" }
    package.products.removeAll { $0.name == "Reach5" }
    package.targets.append(
        .testTarget(
            name: "Reach5MacrosTests",
            dependencies: [
                "Reach5Macros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax"),
            ],
            path: "Tests/Reach5MacrosTests"
        )
    )
}

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

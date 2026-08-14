import XCTest
@testable import Reach5

/// The macro used the way an integrator uses it — from a target that imports `Reach5` and builds for iOS/Mac
/// Catalyst, so the plugin actually runs during that compilation. `Reach5MacrosTests` checks the expansion in
/// isolation on the build machine; this checks that the expansion compiles and means what it should here.
final class WebAuthnOriginMacroUsageTests: XCTestCase {

    func testTheMacroProducesTheOriginItWasGiven() {
        let origin = #WebAuthnOrigin("https://auth.example.com")

        XCTAssertEqual(origin.absoluteString, "https://auth.example.com")
    }

    func testAnOriginFromTheMacroIsAcceptedBySdkConfig() {
        let config = SdkConfig(
            domain: "example.reach5.net",
            clientId: "abc",
            originWebAuthn: #WebAuthnOrigin("https://auth.example.com"))

        XCTAssertEqual(config.webAuthnOrigin, "https://auth.example.com")
    }

    /// The property that makes the macro worth its cost: whatever it accepts, `SdkConfig` accepts too, because
    /// both ask `WebAuthnOrigin.rejection(of:)`/`serialized(_:)`. Were the compile-time rule ever loosened past
    /// the runtime one, this is where it would show — a value the macro let through and the init refuses is a
    /// crash at launch that no macro test would catch.
    func testEveryOriginTheMacroAcceptsAlsoSerializesAtRuntime() {
        let accepted = [
            #WebAuthnOrigin("https://auth.example.com"),
            #WebAuthnOrigin("https://auth.example.com:8443"),
            #WebAuthnOrigin("http://localhost:3000"),
            #WebAuthnOrigin("https://xn--caf-dma.example"),
        ]
        for origin in accepted {
            XCTAssertNotNil(
                SdkConfig.serializedOrigin(origin),
                "the macro accepted '\(origin)' but SdkConfig does not serialize it")
        }
    }
}

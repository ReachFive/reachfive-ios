import XCTest
import AuthenticationServices
@testable import Reach5

@MainActor
final class WebviewLoginRequestTests: XCTestCase {

    private let provider = DummyContextProvider()

    func testDefaultState() {
        XCTAssertEqual(WebviewLoginRequest(presentationContextProvider: provider).state, "state")
    }

    func testProvidedStateIsPreserved() {
        XCTAssertEqual(WebviewLoginRequest(state: "my-state", presentationContextProvider: provider).state, "my-state")
    }

    func testDefaultNonce() {
        XCTAssertEqual(WebviewLoginRequest(presentationContextProvider: provider).nonce, "nonce")
    }

    func testProvidedNonceIsPreserved() {
        XCTAssertEqual(WebviewLoginRequest(nonce: "my-nonce", presentationContextProvider: provider).nonce, "my-nonce")
    }

    func testWebSessionModeDefaultsToSdkScheme() {
        guard case .sdkScheme = WebviewLoginRequest(presentationContextProvider: provider).webSessionMode else {
            return XCTFail("webSessionMode should default to .sdkScheme")
        }
    }

    func testExternalAppModeIsPreserved() {
        let r = WebviewLoginRequest(presentationContextProvider: provider, webSessionMode: .externalApp(URL(string: "https://h/cb")!))
        guard case .externalApp(let link) = r.webSessionMode else {
            return XCTFail("webSessionMode should be .externalApp")
        }
        XCTAssertEqual(link.absoluteString, "https://h/cb")
    }

    func testUniversalLinkModeIsPreserved() {
        let r = WebviewLoginRequest(presentationContextProvider: provider, webSessionMode: .universalLink(URL(string: "https://h/cb")!))
        guard case .universalLink(let link) = r.webSessionMode else {
            return XCTFail("webSessionMode should be .universalLink")
        }
        XCTAssertEqual(link.absoluteString, "https://h/cb")
    }

    func testDefaultLoginUrlFragmentIsNil() {
        XCTAssertNil(WebviewLoginRequest(presentationContextProvider: provider).loginUrlFragment)
    }

    func testProvidedLoginUrlFragmentIsPreserved() {
        let r = WebviewLoginRequest(presentationContextProvider: provider, loginUrlFragment: ["site": "gourmet"])
        XCTAssertEqual(r.loginUrlFragment, ["site": "gourmet"])
    }
}

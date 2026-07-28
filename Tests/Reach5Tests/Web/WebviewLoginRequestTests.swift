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

    func testWebSessionModeDefaultsToCustomScheme() {
        let mode = WebviewLoginRequest(presentationContextProvider: provider).webSessionMode
        guard case .customScheme = mode.callback else {
            return XCTFail("webSessionMode should default to .customScheme")
        }
        XCTAssertNil(mode.redirectUri, "the custom scheme carries no redirect_uri of its own; the SdkConfig's applies")
    }

    func testUniversalLinkModeIsPreserved() throws {
        guard #available(iOS 17.4, *) else { throw XCTSkip("Universal link callback requires iOS 17.4+") }
        let mode = WebviewLoginRequest(presentationContextProvider: provider, webSessionMode: .universalLink(URL(string: "https://h/cb")!)).webSessionMode
        guard case .universalLink(let link) = mode.callback else {
            return XCTFail("webSessionMode should be .universalLink")
        }
        XCTAssertEqual(link.absoluteString, "https://h/cb")
        XCTAssertEqual(mode.redirectUri?.absoluteString, "https://h/cb")
    }

    func testDefaultLoginUrlFragmentIsNil() {
        XCTAssertNil(WebviewLoginRequest(presentationContextProvider: provider).loginUrlFragment)
    }

    func testProvidedLoginUrlFragmentIsPreserved() {
        let r = WebviewLoginRequest(presentationContextProvider: provider, loginUrlFragment: ["site": "gourmet"])
        XCTAssertEqual(r.loginUrlFragment, ["site": "gourmet"])
    }
}

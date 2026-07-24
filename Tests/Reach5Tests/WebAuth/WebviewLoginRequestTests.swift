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
}

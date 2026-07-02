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

    func testCallbackDefaultsToSdkScheme() {
        guard case .sdkScheme = WebviewLoginRequest(presentationContextProvider: provider).callback else {
            return XCTFail("callback should default to .sdkScheme")
        }
    }

    func testExternalAppCallbackIsPreserved() {
        let r = WebviewLoginRequest(presentationContextProvider: provider, callback: .externalApp("https://h/cb"))
        guard case .externalApp(let link) = r.callback else {
            return XCTFail("callback should be .externalApp")
        }
        XCTAssertEqual(link, "https://h/cb")
    }

    func testUniversalLinkInSheetCallbackIsPreserved() {
        let r = WebviewLoginRequest(presentationContextProvider: provider, callback: .universalLinkInSheet("https://h/cb"))
        guard case .universalLinkInSheet(let link) = r.callback else {
            return XCTFail("callback should be .universalLinkInSheet")
        }
        XCTAssertEqual(link, "https://h/cb")
    }
}

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
        let mode = WebviewLoginRequest(presentationContextProvider: provider).webSessionMode
        guard case .customScheme = mode.callback, mode.channel == .inBand else {
            return XCTFail("webSessionMode should default to .sdkScheme (customScheme + inBand)")
        }
    }

    func testExternalAppSchemeModeIsPreserved() {
        let mode = WebviewLoginRequest(presentationContextProvider: provider, webSessionMode: .externalAppScheme).webSessionMode
        guard case .customScheme = mode.callback, mode.channel == .outOfBand else {
            return XCTFail("webSessionMode should be external-app custom scheme")
        }
    }

    func testExternalAppUniversalLinkModeIsPreserved() {
        let mode = WebviewLoginRequest(presentationContextProvider: provider, webSessionMode: .externalAppUniversalLink(URL(string: "https://h/cb")!)).webSessionMode
        guard case .universalLink(let link) = mode.callback, mode.channel == .outOfBand else {
            return XCTFail("webSessionMode should be external-app universal link")
        }
        XCTAssertEqual(link.absoluteString, "https://h/cb")
    }

    func testInSheetUniversalLinkModeIsPreserved() throws {
        guard #available(iOS 17.4, *) else { throw XCTSkip("In-sheet universal link requires iOS 17.4+") }
        let mode = WebviewLoginRequest(presentationContextProvider: provider, webSessionMode: .inSheetUniversalLink(URL(string: "https://h/cb")!)).webSessionMode
        guard case .universalLink(let link) = mode.callback, mode.channel == .inBand else {
            return XCTFail("webSessionMode should be in-sheet universal link")
        }
        XCTAssertEqual(link.absoluteString, "https://h/cb")
    }
}

import XCTest
@testable import Reach5

/// The SDK's three `/oauth/authorize` calls share one basis of parameters and differ only by what they
/// add. That basis is the only testable part of them: everything else goes to the network. These tests
/// pin the expected dictionaries, so a parameter that moves is settled by CI rather than by review.
final class AuthorizeParamsTests: XCTestCase {
    private let pkce = Pkce.generate()

    private func makeReachFive(scope: [String] = []) -> ReachFive {
        let reachFive = ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "testclient"))
        reachFive.scope = scope
        return reachFive
    }

    /// `nil` values stay in the dictionary and are filtered later by `ReachFiveApi`; for comparison, keep
    /// only the keys actually set.
    private func present(_ params: [String: String?]) -> [String: String] {
        params.compactMapValues { $0 }
    }

    func testTheSharedBasisIsTheSameForEveryCall() {
        let params = present(makeReachFive().authorizeParams(pkce: pkce, scope: ["openid"], origin: nil, adding: [:]))

        XCTAssertEqual(params, [
            "client_id": "testclient",
            "response_type": "code",
            "redirect_uri": "reachfive-testclient://callback",
            "scope": "openid",
            "code_challenge": pkce.codeChallenge,
            "code_challenge_method": pkce.codeChallengeMethod,
        ])
    }

    func testLoginCallbackAddsOnlyTheTkn() {
        let params = present(makeReachFive().authorizeParams(pkce: pkce, scope: ["openid"], origin: "test", adding: ["tkn": "the-tkn"]))

        XCTAssertEqual(params["tkn"], "the-tkn")
        XCTAssertEqual(params["origin"], "test")
        XCTAssertNil(params["provider"])
        XCTAssertNil(params["id_token"])
        XCTAssertNil(params["state"])
    }

    func testProviderAddsTheIdTokenNonceAndNames() {
        let nonce = Pkce.generate()
        let params = present(makeReachFive().authorizeParams(pkce: pkce, scope: ["openid"], origin: nil, adding: [
            "provider": "apple:native",
            "id_token": "the-id-token",
            "nonce": nonce.codeVerifier,
            "given_name": "Jane",
            "family_name": "Doe",
        ]))

        XCTAssertEqual(params["provider"], "apple:native")
        XCTAssertEqual(params["id_token"], "the-id-token")
        // the nonce sent to the server is the verifier of the challenge given to the provider
        XCTAssertEqual(params["nonce"], nonce.codeVerifier)
        XCTAssertEqual(params["given_name"], "Jane")
        XCTAssertEqual(params["family_name"], "Doe")
        XCTAssertNil(params["tkn"])
    }

    func testWebviewAddsTheStateAndNonce() {
        let params = present(makeReachFive().authorizeParams(pkce: pkce, scope: ["openid"], origin: nil, adding: [
            "provider": "franceconnect",
            "state": "the-state",
            "nonce": "the-nonce",
        ]))

        XCTAssertEqual(params["state"], "the-state")
        XCTAssertEqual(params["nonce"], "the-nonce")
        XCTAssertNil(params["id_token"])
    }

    /// Optional names left out must not appear in the final URL.
    func testAbsentOptionalsAreNotSent() {
        let params = present(makeReachFive().authorizeParams(pkce: pkce, scope: nil, origin: nil, adding: [
            "given_name": nil,
            "family_name": nil,
        ]))

        XCTAssertNil(params["given_name"])
        XCTAssertNil(params["family_name"])
        XCTAssertNil(params["origin"])
    }

    func testScopeFallsBackToTheSdkScopeWhenNoneIsRequested() {
        let reachFive = makeReachFive(scope: ["openid", "profile"])

        XCTAssertEqual(present(reachFive.authorizeParams(pkce: pkce, scope: nil, origin: nil, adding: [:]))["scope"], "openid profile")
        XCTAssertEqual(present(reachFive.authorizeParams(pkce: pkce, scope: ["email"], origin: nil, adding: [:]))["scope"], "email")
    }

    /// The basis wins over `extra`: a caller cannot accidentally redefine the grant it is asking for.
    func testSharedParametersWinOverColliding() {
        let params = present(makeReachFive().authorizeParams(pkce: pkce, scope: ["openid"], origin: nil, adding: [
            "response_type": "token",
            "client_id": "someone-else",
        ]))

        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["client_id"], "testclient")
    }

    /// End to end on the only call without network. Query item order coming from a Dictionary is not
    /// deterministic, so compare sets and never the absoluteString.
    func testBuildAuthorizeURLCarriesTheParamsPlusPlatformAndSdk() throws {
        let url = makeReachFive(scope: ["openid"]).buildAuthorizeURL(pkce: pkce, state: "the-state", provider: "franceconnect")

        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })

        XCTAssertEqual(components.host, "example.reach5.net")
        XCTAssertEqual(components.path, "/oauth/authorize")
        XCTAssertEqual(items["client_id"], "testclient")
        XCTAssertEqual(items["response_type"], "code")
        XCTAssertEqual(items["scope"], "openid")
        XCTAssertEqual(items["state"], "the-state")
        XCTAssertEqual(items["provider"], "franceconnect")
        XCTAssertEqual(items["code_challenge"], pkce.codeChallenge)
        XCTAssertEqual(items["platform"], "ios")
        XCTAssertNotNil(items["sdk"] ?? nil)
    }

    /// Only the webview call may redirect elsewhere than ``SdkConfig/redirectUri``, and its override has to
    /// reach the query: `/oauth/token` is later handed the same URL, and the server rejects the exchange
    /// when the two disagree.
    func testWebviewCanOverrideTheRedirectUri() throws {
        let reachFive = makeReachFive(scope: ["openid"])
        let elsewhere = try XCTUnwrap(URL(string: "myapp://elsewhere"))

        let overridden = present(reachFive.authorizeParams(pkce: pkce, scope: nil, origin: nil, redirectUri: elsewhere, adding: [:]))
        XCTAssertEqual(overridden["redirect_uri"], "myapp://elsewhere")

        let items = try XCTUnwrap(URLComponents(url: reachFive.buildAuthorizeURL(pkce: pkce, redirectUri: elsewhere), resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "redirect_uri" }?.value, "myapp://elsewhere")

        let byDefault = present(reachFive.authorizeParams(pkce: pkce, scope: nil, origin: nil, adding: [:]))
        XCTAssertEqual(byDefault["redirect_uri"], "reachfive-testclient://callback")
    }
}

import XCTest
@testable import Reach5

/// Les trois appels `/oauth/authorize` du SDK partagent le même socle de paramètres et ne diffèrent que
/// par ce qu'ils ajoutent. C'est la seule partie de ces appels qui soit testable — `ReachFiveApi` n'étant
/// pas abstrait derrière un protocole, tout le reste part sur le réseau. Ces tests figent donc les
/// dictionnaires attendus : un paramètre qui bouge devient une question tranchée par la CI, pas par la
/// relecture.
final class AuthorizeParamsTests: XCTestCase {
    private let pkce = Pkce.generate()

    private func makeReachFive(scope: [String] = []) -> ReachFive {
        let reachFive = ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "testclient"))
        reachFive.scope = scope
        return reachFive
    }

    /// Les valeurs `nil` sont conservées dans le dictionnaire et filtrées plus tard par `ReachFiveApi` ;
    /// pour comparer, on ne garde que les clés réellement renseignées.
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
        // le nonce envoyé au serveur est le verifier du challenge donné au provider
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

    /// Les noms optionnels non fournis ne doivent pas apparaître dans l'URL finale.
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

    /// Le socle gagne sur `extra` : un appelant ne peut pas redéfinir par accident le grant qu'il demande.
    func testSharedParametersWinOverColliding() {
        let params = present(makeReachFive().authorizeParams(pkce: pkce, scope: ["openid"], origin: nil, adding: [
            "response_type": "token",
            "client_id": "someone-else",
        ]))

        XCTAssertEqual(params["response_type"], "code")
        XCTAssertEqual(params["client_id"], "testclient")
    }

    /// Bout en bout sur le seul appel sans réseau. L'ordre des query items d'un Dictionary n'est pas
    /// déterministe : on compare des ensembles, jamais l'absoluteString.
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
        XCTAssertNotNil(items["sdk"])
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

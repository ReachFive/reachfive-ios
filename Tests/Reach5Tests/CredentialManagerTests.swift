import XCTest
import AuthenticationServices
@testable import Reach5

@MainActor
final class CredentialManagerRegistrationRequestTests: XCTestCase {

    private func makeOptions(challenge: String, userID: String) -> RegistrationOptions {
        RegistrationOptions(
            friendlyName: "iPhone de Test",
            options: CredentialCreationOptions(
                publicKey: R5PublicKeyCredentialCreationOptions(
                    rp: R5PublicKeyCredentialRpEntity(id: "example.reach5.net", name: "Example"),
                    user: R5PublicKeyCredentialUserEntity(id: userID, displayName: "Test", name: "test@example.com"),
                    challenge: challenge,
                    pubKeyCredParams: [R5PublicKeyCredentialParameter(alg: -7, type: "public-key")],
                    timeout: nil,
                    excludeCredentials: nil,
                    authenticatorSelection: nil,
                    attestation: "none"
                )
            )
        )
    }

    @available(iOS 16.0, *)
    func testNominalCaseBuildsRequestWithRelyingParty() throws {
        let request = try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "AQID", userID: "BAUG"), friendlyName: "iPhone de Test")

        let registrationRequest = try XCTUnwrap(request as? ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest)
        XCTAssertEqual(registrationRequest.relyingPartyIdentifier, "example.reach5.net")
        XCTAssertEqual(registrationRequest.name, "iPhone de Test")
    }

    @available(iOS 16.0, *)
    func testUnreadableChallengeThrowsTechnicalError() {
        XCTAssertThrowsError(try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "%%%", userID: "BAUG"), friendlyName: "iPhone de Test")) { error in
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("unreadable challenge"))
        }
    }

    @available(iOS 16.0, *)
    func testUnreadableUserIDThrowsTechnicalError() {
        XCTAssertThrowsError(try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "AQID", userID: "%%%"), friendlyName: "iPhone de Test")) { error in
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("unreadable userID"))
        }
    }
}

/// La construction des requêtes système pour le login modal, testée sans réseau : le réseau est
/// coupé en substituant `fetchAuthenticationOptions` (appel réel par défaut, cf. signature de
/// `buildAuthorizationRequests`).
@MainActor
final class CredentialManagerAuthorizationRequestsTests: XCTestCase {

    private let reachFive = ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "testclient"))
    private lazy var webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFive.sdkConfig.clientId, origin: "https://example.reach5.net", scope: nil)

    private func failFetch(_: ReachFive, _: WebAuthnLoginRequest) async throws -> AuthenticationOptions {
        XCTFail("fetchAuthenticationOptions ne doit pas être appelé")
        throw ReachFiveError.TechnicalError(reason: "unexpected fetch")
    }

    private func failMake(_ options: AuthenticationOptions) throws -> ASAuthorizationRequest {
        XCTFail("makeAuthorization ne doit pas être appelé")
        throw ReachFiveError.TechnicalError(reason: "unexpected make")
    }

    func testPasswordBuildsASinglePasswordRequest() async throws {
        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Password],fetchAuthenticationOptions: failFetch, makeAuthorization: failMake)

        XCTAssertEqual(built.requests.count, 1)
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
        guard case .none = built.extra else {
            return XCTFail("expected .none, got \(built.extra)")
        }
    }

    func testSignInWithAppleCarriesProviderScopesAndNonce() async throws {
        let providerConfig = try JSONDecoder().decode(ProviderConfig.self, from: Data(#"{"provider": "apple", "variant": "native", "scope": ["email", "name"]}"#.utf8))
        let appleProvider = ConfiguredAppleProvider(reachFive: reachFive, providerConfig: providerConfig, clientConfigResponse: ClientConfigResponse(scope: "openid profile", sms: false))

        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.SignInWithApple], appleProvider: appleProvider, fetchAuthenticationOptions: failFetch, makeAuthorization: failMake)

        let appleRequest = try XCTUnwrap(built.requests.first as? ASAuthorizationAppleIDRequest)
        XCTAssertEqual(appleRequest.requestedScopes, [.email, .fullName])

        guard case let .signInWithApple(nonce, provider) = built.extra else {
            return XCTFail("expected .signInWithApple, got \(built.extra)")
        }
        // le nonce envoyé à Apple est le code challenge ; le verifier correspondant partira au serveur
        XCTAssertEqual(appleRequest.nonce, nonce.codeChallenge)
        XCTAssertTrue(provider === appleProvider)
    }

    @available(iOS 16.0, *)
    func testPasskeyAloneFailureThrows() async {
        do {
            _ = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Passkey], fetchAuthenticationOptions: { _, _ in throw ReachFiveError.TechnicalError(reason: "network down") }, makeAuthorization: failMake)
            XCTFail("expected the fetch error to propagate")
        } catch {
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertEqual(reason, "network down")
        }
    }

    @available(iOS 16.0, *)
    func testPasskeyFailureIsSwallowedWhenCombinedWithAnotherType() async throws {
        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Passkey, .Password], fetchAuthenticationOptions: { _, _ in throw ReachFiveError.TechnicalError(reason: "network down") }, makeAuthorization: failMake)

        XCTAssertEqual(built.requests.count, 1, "la requête password doit survivre à l'échec passkey")
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
    }

    @available(iOS 16.0, *)
    func testPasskeyPassesFetchedOptionsToMakeAuthorization() async throws {
        let options = AuthenticationOptions(publicKey: R5PublicKeyCredentialRequestOptions(challenge: "AQID", timeout: nil, rpId: "example.reach5.net", allowCredentials: nil, userVerification: "preferred"))
        let placeholder = ASAuthorizationPasswordProvider().createRequest()

        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Passkey], fetchAuthenticationOptions: { _, _ in options }, makeAuthorization: { received in
            XCTAssertTrue(received === options)
            return placeholder
        })

        XCTAssertEqual(built.requests.count, 1)
        XCTAssertTrue(built.requests.first === placeholder)
    }
}

import AuthenticationServices
import XCTest
@testable import Reach5

@MainActor
final class CredentialManagerRegistrationRequestTests: XCTestCase {
    /// Le friendlyName des options est volontairement différent de celui demandé par l'application :
    /// c'est l'intention de l'application qui doit nommer la passkey, pas l'écho du serveur.
    private func makeOptions(challenge: String, userID: String) -> RegistrationOptions {
        RegistrationOptions(
            friendlyName: "nom renvoyé par le serveur",
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
    func testNominalCaseBuildsRequestWithRelyingPartyAndRequestedName() throws {
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

/// La construction des requêtes d'assertion, pendant symétrique de l'enregistrement.
@MainActor
final class CredentialManagerAssertionRequestTests: XCTestCase {
    private func makeOptions(challenge: String = "AQID", allowCredentials: [R5PublicKeyCredentialDescriptor]? = nil) -> AuthenticationOptions {
        AuthenticationOptions(publicKey: R5PublicKeyCredentialRequestOptions(challenge: challenge, timeout: nil, rpId: "example.reach5.net", allowCredentials: allowCredentials, userVerification: "preferred"))
    }

    /// Auto-fill et connexion modale : l'utilisateur choisit parmi toutes ses passkeys du relying party.
    @available(iOS 16.0, *)
    func testUnrestrictedRequestListsNoAllowedCredential() throws {
        let request = try CredentialManager().makePasskeyAssertionRequest(makeOptions(allowCredentials: [R5PublicKeyCredentialDescriptor(type: "public-key", id: "AQID")]), restrictedToAllowedCredentials: false)

        let assertionRequest = try XCTUnwrap(request as? ASAuthorizationPlatformPublicKeyCredentialAssertionRequest)
        XCTAssertEqual(assertionRequest.relyingPartyIdentifier, "example.reach5.net")
        XCTAssertTrue(assertionRequest.allowedCredentials.isEmpty)
    }

    /// Connexion non-discoverable : le compte est connu, la requête est restreinte aux credentials du serveur.
    @available(iOS 16.0, *)
    func testRestrictedRequestCarriesTheDecodedAllowedCredentials() throws {
        let request = try CredentialManager().makePasskeyAssertionRequest(makeOptions(allowCredentials: [R5PublicKeyCredentialDescriptor(type: "public-key", id: "AQID")]), restrictedToAllowedCredentials: true)

        let assertionRequest = try XCTUnwrap(request as? ASAuthorizationPlatformPublicKeyCredentialAssertionRequest)
        XCTAssertEqual(assertionRequest.allowedCredentials.map(\.credentialID), [Data([0x01, 0x02, 0x03])])
    }

    @available(iOS 16.0, *)
    func testRestrictedRequestWithoutAllowedCredentialsThrowsAuthFailure() {
        XCTAssertThrowsError(try CredentialManager().makePasskeyAssertionRequest(makeOptions(allowCredentials: nil), restrictedToAllowedCredentials: true)) { error in
            guard case let ReachFiveError.AuthFailure(reason, _) = error else {
                return XCTFail("expected .AuthFailure, got \(error)")
            }
            XCTAssertTrue(reason.contains("no allowCredentials returned"))
        }
    }

    @available(iOS 16.0, *)
    func testUnreadableChallengeThrowsTechnicalError() {
        XCTAssertThrowsError(try CredentialManager().makePasskeyAssertionRequest(makeOptions(challenge: "%%%"), restrictedToAllowedCredentials: false)) { error in
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("unreadable challenge"))
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

    func testPasswordBuildsASinglePasswordRequest() async throws {
        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Password], fetchAuthenticationOptions: failFetch)

        XCTAssertEqual(built.requests.count, 1)
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
        XCTAssertNil(built.siwa)
    }

    func testSignInWithAppleCarriesProviderScopesAndNonce() async throws {
        let providerConfig = try JSONDecoder().decode(ProviderConfig.self, from: Data(#"{"provider": "apple", "variant": "native", "scope": ["email", "name"]}"#.utf8))
        let appleProvider = ConfiguredAppleProvider(reachFive: reachFive, providerConfig: providerConfig, clientConfigResponse: ClientConfigResponse(scope: "openid profile", sms: false))

        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.SignInWithApple], appleProvider: appleProvider, fetchAuthenticationOptions: failFetch)

        let appleRequest = try XCTUnwrap(built.requests.first as? ASAuthorizationAppleIDRequest)
        XCTAssertEqual(appleRequest.requestedScopes, [.email, .fullName])

        let siwa = try XCTUnwrap(built.siwa)
        // le nonce envoyé à Apple est le code challenge ; le verifier correspondant partira au serveur
        XCTAssertEqual(appleRequest.nonce, siwa.nonce.codeChallenge)
        XCTAssertTrue(siwa.provider === appleProvider)
    }

    @available(iOS 16.0, *)
    func testPasskeyAloneFailureThrows() async {
        do {
            _ = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Passkey], fetchAuthenticationOptions: { _, _ in throw ReachFiveError.TechnicalError(reason: "network down") })
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
        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Passkey, .Password], fetchAuthenticationOptions: { _, _ in throw ReachFiveError.TechnicalError(reason: "network down") })

        XCTAssertEqual(built.requests.count, 1, "la requête password doit survivre à l'échec passkey")
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
    }

    /// Les options récupérées auprès du serveur sont bien celles qui construisent la requête d'assertion.
    @available(iOS 16.0, *)
    func testPasskeyBuildsAnAssertionRequestFromTheFetchedOptions() async throws {
        let options = AuthenticationOptions(publicKey: R5PublicKeyCredentialRequestOptions(challenge: "AQID", timeout: nil, rpId: "fetched.reach5.net", allowCredentials: nil, userVerification: "preferred"))

        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Passkey], fetchAuthenticationOptions: { _, _ in options })

        let assertionRequest = try XCTUnwrap(built.requests.first as? ASAuthorizationPlatformPublicKeyCredentialAssertionRequest)
        XCTAssertEqual(assertionRequest.relyingPartyIdentifier, "fetched.reach5.net")
    }
}

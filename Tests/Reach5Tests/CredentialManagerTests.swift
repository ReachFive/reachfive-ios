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

    func testRestrictedRequestWithoutAllowedCredentialsThrowsAuthFailure() {
        XCTAssertThrowsError(try CredentialManager().makePasskeyAssertionRequest(makeOptions(allowCredentials: nil), restrictedToAllowedCredentials: true)) { error in
            guard case let ReachFiveError.AuthFailure(reason, _) = error else {
                return XCTFail("expected .AuthFailure, got \(error)")
            }
            XCTAssertTrue(reason.contains("no allowCredentials returned"))
        }
    }

    func testUnreadableChallengeThrowsTechnicalError() {
        XCTAssertThrowsError(try CredentialManager().makePasskeyAssertionRequest(makeOptions(challenge: "%%%"), restrictedToAllowedCredentials: false)) { error in
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("unreadable challenge"))
        }
    }
}

/// L'assemblage du lot de requêtes système pour le login modal, fonction pure testée sans réseau : le
/// fetch de la passkey, quand il a lieu, est fait par l'appelant et `passkey` en porte le résultat.
@MainActor
final class CredentialManagerAuthorizationRequestsTests: XCTestCase {
    private let reachFive = ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "testclient"))

    /// Une requête d'assertion quelconque : le builder ne fait que la placer dans le lot.
    @available(iOS 16.0, *)
    private var somePasskeyRequest: ASAuthorizationRequest {
        ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.reach5.net")
            .createCredentialAssertionRequest(challenge: Data())
    }

    func testPasswordBuildsASinglePasswordRequest() throws {
        let built = try CredentialManager().buildAuthorizationRequests(authorizing: [.Password], appleProvider: nil, passkey: nil)

        XCTAssertEqual(built.requests.count, 1)
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
        XCTAssertNil(built.siwa)
    }

    func testSignInWithAppleCarriesProviderScopesAndNonce() throws {
        let providerConfig = try JSONDecoder().decode(ProviderConfig.self, from: Data(#"{"provider": "apple", "variant": "native", "scope": ["email", "name"]}"#.utf8))
        let appleProvider = ConfiguredAppleProvider(reachFive: reachFive, providerConfig: providerConfig, clientConfigResponse: ClientConfigResponse(scope: "openid profile", sms: false))

        let built = try CredentialManager().buildAuthorizationRequests(authorizing: [.SignInWithApple], appleProvider: appleProvider, passkey: nil)

        let appleRequest = try XCTUnwrap(built.requests.first as? ASAuthorizationAppleIDRequest)
        XCTAssertEqual(appleRequest.requestedScopes, [.email, .fullName])

        let siwa = try XCTUnwrap(built.siwa)
        // le nonce envoyé à Apple est le code challenge ; le verifier correspondant partira au serveur
        XCTAssertEqual(appleRequest.nonce, siwa.nonce.codeChallenge)
        XCTAssertTrue(siwa.provider === appleProvider)
    }

    @available(iOS 16.0, *)
    func testPasskeyAloneFailureThrows() {
        XCTAssertThrowsError(try CredentialManager().buildAuthorizationRequests(authorizing: [.Passkey], appleProvider: nil, passkey: .failure(ReachFiveError.TechnicalError(reason: "network down")))) { error in
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertEqual(reason, "network down")
        }
    }

    @available(iOS 16.0, *)
    func testPasskeyFailureIsSwallowedWhenCombinedWithAnotherType() throws {
        let built = try CredentialManager().buildAuthorizationRequests(authorizing: [.Passkey, .Password], appleProvider: nil, passkey: .failure(ReachFiveError.TechnicalError(reason: "network down")))

        XCTAssertEqual(built.requests.count, 1, "la requête password doit survivre à l'échec passkey")
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
    }

    /// L'ordre des requêtes est un contrat Apple : le système présente les credentials dans cet ordre.
    @available(iOS 16.0, *)
    func testRequestsFollowTheRequestedOrder() throws {
        let passkey: Result<ASAuthorizationRequest, Error> = .success(somePasskeyRequest)

        let passkeyFirst = try CredentialManager().buildAuthorizationRequests(authorizing: [.Passkey, .Password], appleProvider: nil, passkey: passkey)
        XCTAssertTrue(passkeyFirst.requests[0] is ASAuthorizationPlatformPublicKeyCredentialAssertionRequest)
        XCTAssertTrue(passkeyFirst.requests[1] is ASAuthorizationPasswordRequest)

        let passwordFirst = try CredentialManager().buildAuthorizationRequests(authorizing: [.Password, .Passkey], appleProvider: nil, passkey: passkey)
        XCTAssertTrue(passwordFirst.requests[0] is ASAuthorizationPasswordRequest)
        XCTAssertTrue(passwordFirst.requests[1] is ASAuthorizationPlatformPublicKeyCredentialAssertionRequest)
    }
}

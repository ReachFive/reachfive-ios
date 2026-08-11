import AuthenticationServices
import XCTest
@testable import Reach5

@MainActor
final class CredentialManagerRegistrationRequestTests: XCTestCase {
    /// The options' friendlyName deliberately differs from the one the app asked for: the app's intent
    /// should name the passkey, not the server's echo.
    private func makeOptions(challenge: String, userID: String) -> RegistrationOptions {
        RegistrationOptions(
            friendlyName: "name returned by the server",
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
        let request = try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "AQID", userID: "BAUG"), friendlyName: "Test iPhone")

        let registrationRequest = try XCTUnwrap(request as? ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest)
        XCTAssertEqual(registrationRequest.relyingPartyIdentifier, "example.reach5.net")
        XCTAssertEqual(registrationRequest.name, "Test iPhone")
    }

    /// L'enregistrement explicite — inscription, ajout, réinitialisation — présente une feuille système :
    /// le style conditionnel doit rester l'exception qu'on demande.
    @available(iOS 18.0, *)
    func testRequestIsStandardByDefault() throws {
        let request = try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "AQID", userID: "BAUG"), friendlyName: "iPhone de Test")

        let registrationRequest = try XCTUnwrap(request as? ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest)
        XCTAssertEqual(registrationRequest.requestStyle, .standard)
    }

    /// L'upgrade automatique : ce seul drapeau rend la création silencieuse, tout le reste de la requête
    /// est celui d'un enregistrement ordinaire.
    @available(iOS 18.0, *)
    func testConditionalRequestCarriesTheConditionalStyle() throws {
        let request = try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "AQID", userID: "BAUG"), friendlyName: "iPhone de Test", conditional: true)

        let registrationRequest = try XCTUnwrap(request as? ASAuthorizationPlatformPublicKeyCredentialRegistrationRequest)
        XCTAssertEqual(registrationRequest.requestStyle, .conditional)
        XCTAssertEqual(registrationRequest.relyingPartyIdentifier, "example.reach5.net")
        XCTAssertEqual(registrationRequest.name, "iPhone de Test")
    }

    @available(iOS 16.0, *)
    func testUnreadableChallengeThrowsTechnicalError() {
        XCTAssertThrowsError(try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "%%%", userID: "BAUG"), friendlyName: "Test iPhone")) { error in
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("unreadable challenge"))
        }
    }

    @available(iOS 16.0, *)
    func testUnreadableUserIDThrowsTechnicalError() {
        XCTAssertThrowsError(try CredentialManager().makeCredentialRegistrationRequest(from: makeOptions(challenge: "AQID", userID: "%%%"), friendlyName: "Test iPhone")) { error in
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("unreadable userID"))
        }
    }
}

/// Assertion request construction, the symmetric counterpart of registration.
@MainActor
final class CredentialManagerAssertionRequestTests: XCTestCase {
    private func makeOptions(challenge: String = "AQID", allowCredentials: [R5PublicKeyCredentialDescriptor]? = nil) -> AuthenticationOptions {
        AuthenticationOptions(publicKey: R5PublicKeyCredentialRequestOptions(challenge: challenge, timeout: nil, rpId: "example.reach5.net", allowCredentials: allowCredentials, userVerification: "preferred"))
    }

    /// Auto-fill and modal sign-in: the user picks among all their passkeys for the relying party.
    @available(iOS 16.0, *)
    func testUnrestrictedRequestListsNoAllowedCredential() throws {
        let request = try CredentialManager().makePasskeyAssertionRequest(makeOptions(allowCredentials: [R5PublicKeyCredentialDescriptor(type: "public-key", id: "AQID")]), restrictedToAllowedCredentials: false)

        let assertionRequest = try XCTUnwrap(request as? ASAuthorizationPlatformPublicKeyCredentialAssertionRequest)
        XCTAssertEqual(assertionRequest.relyingPartyIdentifier, "example.reach5.net")
        XCTAssertTrue(assertionRequest.allowedCredentials.isEmpty)
    }

    /// Non-discoverable sign-in: the account is known, so the request is restricted to the server's credentials.
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

/// System request construction for the modal login, tested without network by substituting
/// `fetchAuthenticationOptions`.
@MainActor
final class CredentialManagerAuthorizationRequestsTests: XCTestCase {
    private let reachFive = ReachFive(sdkConfig: SdkConfig(domain: "example.reach5.net", clientId: "testclient"))
    private lazy var webAuthnLoginRequest = WebAuthnLoginRequest(clientId: reachFive.sdkConfig.clientId, origin: "https://example.reach5.net", scope: nil)

    private func failFetch(_: ReachFive, _: WebAuthnLoginRequest) async throws -> AuthenticationOptions {
        XCTFail("fetchAuthenticationOptions should not be called")
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
        // the nonce sent to Apple is the code challenge; the matching verifier goes to the server
        XCTAssertEqual(appleRequest.nonce, siwa.nonce.codeChallenge)
        XCTAssertTrue(siwa.provider === appleProvider)
    }

    /// Without an Apple provider the request could not be completed: requested alone, it must fail
    /// before anything is presented to the user, not after Face ID.
    func testSignInWithAppleAloneSurfacesTheMissingProvider() async {
        do {
            _ = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.SignInWithApple], fetchAuthenticationOptions: failFetch)
            XCTFail("expected the missing provider to surface")
        } catch {
            guard case let ReachFiveError.TechnicalError(reason, _) = error else {
                return XCTFail("expected .TechnicalError, got \(error)")
            }
            XCTAssertTrue(reason.contains("no Apple provider"))
        }
    }

    /// Combined with another type, the missing Apple provider is dropped: the password still suffices.
    func testSignInWithAppleIsDroppedWhenAnotherTypeCanStillSucceed() async throws {
        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.SignInWithApple, .Password], fetchAuthenticationOptions: failFetch)

        XCTAssertEqual(built.requests.count, 1, "the password request must survive the missing Apple provider")
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
        XCTAssertNil(built.siwa)
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

        XCTAssertEqual(built.requests.count, 1, "the password request must survive the passkey failure")
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
    }

    @available(iOS 16.0, *)
    func testSignInWithAppleIsDroppedAndPasskeyFailureIsSwallowedWhenCombinedWithAnotherType() async throws {
        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.SignInWithApple, .Passkey, .Password], fetchAuthenticationOptions: { _, _ in throw ReachFiveError.TechnicalError(reason: "network down") })

        XCTAssertEqual(built.requests.count, 1, "the password request must survive both the passkey and Sign In With Apple failures")
        XCTAssertTrue(built.requests.first is ASAuthorizationPasswordRequest)
    }

    /// The options fetched from the server are the ones that build the assertion request.
    @available(iOS 16.0, *)
    func testPasskeyBuildsAnAssertionRequestFromTheFetchedOptions() async throws {
        let options = AuthenticationOptions(publicKey: R5PublicKeyCredentialRequestOptions(challenge: "AQID", timeout: nil, rpId: "fetched.reach5.net", allowCredentials: nil, userVerification: "preferred"))

        let built = try await CredentialManager().buildAuthorizationRequests(webAuthnLoginRequest, reachFive: reachFive, authorizing: [.Passkey], fetchAuthenticationOptions: { _, _ in options })

        let assertionRequest = try XCTUnwrap(built.requests.first as? ASAuthorizationPlatformPublicKeyCredentialAssertionRequest)
        XCTAssertEqual(assertionRequest.relyingPartyIdentifier, "fetched.reach5.net")
    }
}

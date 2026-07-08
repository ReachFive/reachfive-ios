import XCTest
import AuthenticationServices
@testable import Reach5

final class CredentialManagerErrorMappingTests: XCTestCase {

    func testCanceledBecomesAuthCanceled() {
        let error = ASAuthorizationError(.canceled)

        let result = CredentialManager.adapt(error)

        guard case .AuthCanceled = result else {
            return XCTFail("expected .AuthCanceled, got \(result)")
        }
    }

    func testOtherASAuthorizationErrorBecomesTechnicalErrorWithCode() {
        let error = ASAuthorizationError(.failed)

        let result = CredentialManager.adapt(error)

        guard case let .TechnicalError(reason, _) = result else {
            return XCTFail("expected .TechnicalError, got \(result)")
        }
        XCTAssertTrue(reason.contains("ASAuthorizationError \(ASAuthorizationError.Code.failed.rawValue)"), "le code de l'erreur doit apparaître dans la raison : \(reason)")
    }

    func testNonASAuthorizationErrorBecomesTechnicalError() {
        let error = NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])

        let result = CredentialManager.adapt(error)

        guard case let .TechnicalError(reason, _) = result else {
            return XCTFail("expected .TechnicalError, got \(result)")
        }
        XCTAssertEqual(reason, "boom")
    }
}

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

import XCTest
@testable import Reach5

/// Couvre le mapping des codes d'erreur d'`ASWebAuthenticationSession` vers `ReachFiveError`.
final class WebAuthenticationErrorMappingTests: XCTestCase {

    private func error(_ code: Int) -> NSError {
        NSError(domain: "com.apple.AuthenticationServices.WebAuthenticationSession", code: code)
    }

    func testCanceledMapsToAuthCanceled() {
        guard case .AuthCanceled = WebAuthenticationSession.reachFiveError(for: error(1)) else {
            return XCTFail("code 1 (canceledLogin) doit donner .AuthCanceled")
        }
    }

    func testPresentationContextNotProvidedMapsToTechnical() {
        guard case .TechnicalError = WebAuthenticationSession.reachFiveError(for: error(2)) else {
            return XCTFail("code 2 doit donner .TechnicalError")
        }
    }

    func testPresentationContextInvalidMapsToTechnical() {
        guard case .TechnicalError = WebAuthenticationSession.reachFiveError(for: error(3)) else {
            return XCTFail("code 3 doit donner .TechnicalError")
        }
    }

    func testUnknownCodeMapsToTechnical() {
        guard case .TechnicalError = WebAuthenticationSession.reachFiveError(for: error(999)) else {
            return XCTFail("code inconnu doit donner .TechnicalError")
        }
    }
}

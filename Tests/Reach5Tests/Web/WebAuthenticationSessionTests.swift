import XCTest
@testable import Reach5

/// `WebAuthenticationSession`'s lifecycle, for the little of it that is reachable without presenting a sheet.
@MainActor
final class WebAuthenticationSessionTests: XCTestCase {

    private func makeSession() -> WebAuthenticationSession {
        WebAuthenticationSession(baseScheme: "reachfive-clientId",
                                 sdkRedirectUri: URL(string: "reachfive-clientId://callback")!)
    }

    /// Outside a login the out-of-band channel is not armed, even for a URL perfectly shaped for this SDK:
    /// what decides is `expectedCallback` (nil at rest), not the shape of the URL. The host app must get its
    /// link back (`false`), not see it swallowed by the SDK.
    func testTryCompleteMatchesNothingOutsideALogin() {
        let session = makeSession()
        for url in ["reachfive-clientId://callback?code=abc",
                    "reachfive-clientId://callback?code=abc&state=x",
                    "reachfive-clientId://callback/?code=abc",
                    "reachfive-clientId://callback?error=access_denied"] {
            XCTAssertFalse(session.tryComplete(externalCallbackURL: URL(string: url)!), url)
        }
    }
}
